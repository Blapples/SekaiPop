#!/usr/bin/env python3
"""scrcpy session manager for the SekaiPop phone mirror.

A port of p3drovfx's illogical-impulse `scrcpy_session_manager.py`, cut down to what a mirror
needs (no virtual displays, no app list, no recording). The shell starts ONE of these and
talks to it with one JSON object per line on stdin; it answers with one JSON object per line
on stdout. Nothing else is ever written to stdout.

  shell -> manager
    {"cmd": "launch", "id": "embed", "target_args": ["-s", "SERIAL"], "extra_args": [...],
     "auto_unlock": true}
    {"cmd": "stop", "id": "embed"}        {"cmd": "stop_all"}
    {"cmd": "keepalive", "id": "embed"}   {"cmd": "focus", "id": "window"}

  manager -> shell
    {"event": "started", "id": ..., "pid": ..., "title": ...}
    {"event": "waiting", "id": ..., "reason": "locked" | "unreachable", ...}
    {"event": "exited",  "id": ..., "code": N, "error": "first ERROR line of scrcpy",
                  "deliberate": true when a stop was asked for}
    {"event": "error",   "id": ..., "message": ...}

Why a manager at all and not a Process per scrcpy in QML: scrcpy needs the phone to be
reachable AND unlocked before it is worth starting, adbd restarts (and drops every
connection) each time the phone is unlocked, and the shell has to hear why a window died.
Waiting for that is a loop with sleeps, which belongs in a script and not in a binding.
"""
import argparse
import json
import re
import signal
import subprocess
import sys
import threading
import time

# Its own title so the shell never mistakes the throwaway unlock mirror for a real session.
UNLOCK_WINDOW_TITLE = "sekai-phone-unlock"


def title_for(session_id):
    # services/PhoneMirrorService.qml and PhoneMirror.js `windowTitle()` build the same
    # string; the Hyprland rules (hypr/hyprland/rules.lua) match on it.
    return "sekai-phone-" + str(session_id).replace(":", "_")


def _default_sigint():
    # The shell starts this process with SIGINT ignored, and an ignored signal survives exec.
    # Children get it back.
    signal.signal(signal.SIGINT, signal.SIG_DFL)


class ScrcpySessionManager:
    # The embedded mirror is the one session the user cannot see or close for themselves: it
    # waits behind the panel that paints its picture. Orphaning it would leave the phone
    # encoding video for a window nobody will ever look at again, so it goes down with the
    # shell. The windowed session is the user's, and a shell reload is no reason to close it.
    SHELL_OWNED = ("embed",)

    # This process outlives a config reload with its children still running, and the fresh
    # shell has no memory of having asked for them. So a session with no window of its own
    # is held open by the shell repeating that it still wants it, and ends when that stops.
    KEEPALIVE_TIMEOUT = 15.0

    def __init__(self):
        self.lock = threading.Lock()
        self.processes = {}     # session_id -> subprocess.Popen
        self.session_info = {}  # session_id -> dict
        self.starting = set()   # session_ids whose launch thread is still running
        self.deliberate = set() # session_ids the user asked to stop
        self.keepalives = {}    # session_id -> when the shell last said it still wants it
        self.wait_failures = {} # session_id -> why its launch was never delivered
        self.emit_lock = threading.Lock()
        self.running = True

    def emit(self, event_data):
        # Every session has its own thread and they all share this stream; one write per
        # event, under a lock, so two events can never run into one unparseable line.
        try:
            line = json.dumps(event_data) + "\n"
            with self.emit_lock:
                sys.stdout.write(line)
                sys.stdout.flush()
        except Exception as e:
            sys.stderr.write("Error emitting event: %s\n" % e)

    # ------------------------------------------------------------------ adb

    def resolve_adb_target(self, target_args=None):
        """Pick the serial to hand scrcpy.

        The shell already chose one, so it wins as long as the phone still answers on it.
        Only when it has gone stale does this fall back to whatever `adb devices` reports,
        and there a cable beats Wi-Fi, and a pinned :5555 beats a wireless-debugging port
        that Android re-rolls whenever adbd restarts.
        """
        wanted = ""
        if target_args and len(target_args) >= 2 and target_args[0] in ("-s", "--serial"):
            wanted = str(target_args[1])

        try:
            res = subprocess.run(["adb", "devices"], capture_output=True, text=True, timeout=4)
            usb_devices = []
            ip_devices = []
            for line in res.stdout.splitlines():
                line = line.strip()
                if not line or line.startswith("List of") or line.startswith("*"):
                    continue
                parts = line.split()
                if len(parts) >= 2 and parts[1] == "device":
                    serial = parts[0]
                    if ":" in serial or "._adb-tls-" in serial:
                        ip_devices.append(serial)
                    else:
                        usb_devices.append(serial)

            if wanted and (wanted in usb_devices or wanted in ip_devices):
                return ["-s", wanted]
            if usb_devices:
                return ["-s", usb_devices[0]]
            # The port is what goes stale, not the address: with two phones on the network,
            # falling back must not land on the other one.
            if ":" in wanted:
                host = wanted.rsplit(":", 1)[0] + ":"
                same_host = [s for s in ip_devices if s.startswith(host)]
                if same_host:
                    ip_devices = same_host
            pinned = [s for s in ip_devices if s.endswith(":5555")]
            if pinned:
                return ["-s", pinned[0]]
            if ip_devices:
                return ["-s", ip_devices[0]]
        except Exception:
            pass

        return target_args or []

    # Two independent flags, because neither alone covers every state. `isKeyguardShowing`
    # misses a trusted lockscreen (Smart Lock: the device counts as unlocked, but the swipe
    # screen is still up), and KeyguardStateMonitor's `mIsShowing` tracks whether the
    # lockscreen is actually on screen. `secure` comes along: a secure keyguard means the PIN
    # pad is a FLAG_SECURE surface, so scrcpy can only ever show black there and the user has
    # to be told rather than left staring at it.
    KEYGUARD_QUERY = (
        "dumpsys window 2>/dev/null | awk '"
        "/isKeyguardShowing=/ {print \"showing=\" ($0 ~ /=true/ ? \"true\" : \"false\")} "
        "/KeyguardStateMonitor/ {k=1} "
        "k && /mIsShowing=/ {print \"showing=\" ($0 ~ /=true/ ? \"true\" : \"false\"); k=0} "
        "/KeyguardServiceDelegate/ {d=1} "
        "d && /secure=/ {print \"secure=\" ($0 ~ /=true/ ? \"true\" : \"false\"); d=0}'"
    )

    def keyguard_state(self, target_args):
        """(showing, secure). `showing` is None when the phone can't be asked."""
        cmd = ["adb"] + list(target_args) + ["shell", self.KEYGUARD_QUERY]
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=6)
        except Exception:
            return (None, False)
        if res.returncode != 0:
            return (None, False)
        lines = [ln.strip() for ln in res.stdout.splitlines() if "=" in ln]
        shown = [ln for ln in lines if ln.startswith("showing=")]
        if not shown:
            # The phone answered but its dump has neither flag (another Android version, another
            # vendor). Not knowing must not read as "unreachable": that would hold every launch
            # back until it times out. Launch as if unlocked.
            return (False, False)
        return (any(ln == "showing=true" for ln in shown),
                any(ln == "secure=true" for ln in lines))

    def _display_size(self, target_args):
        try:
            res = subprocess.run(["adb"] + list(target_args) + ["shell", "wm size"],
                                 capture_output=True, text=True, timeout=6)
        except Exception:
            return None
        found = re.findall(r"(\d+)x(\d+)", res.stdout)
        if not found:
            return None
        return int(found[-1][0]), int(found[-1][1])

    def _adb_shell(self, target_args, script, timeout=6):
        try:
            subprocess.run(["adb"] + list(target_args) + ["shell", script],
                           capture_output=True, text=True, timeout=timeout)
            return True
        except Exception:
            return False

    def _swipe_unlock(self, target_args):
        """Wake the phone and swipe the lockscreen up.

        That clears a swipe-only or trusted keyguard, and brings a secure one straight to its
        PIN pad. WAKEUP, not POWER: it never puts a woken phone back to sleep. The pause
        matters: a swipe sent in the same breath as the wake is swallowed.
        """
        size = self._display_size(target_args)
        if size is None:
            return
        width, height = size
        column = str(width // 2)
        self._adb_shell(
            target_args,
            "input keyevent 224; sleep 1; input swipe %s %d %s %d 200"
            % (column, int(height * 0.8), column, int(height * 0.25)))

    def _spawn_unlock_helper(self, resolved_target):
        """A plain mirror of the phone screen, purely so a PIN can be typed from the desktop.

        Deliberately built without --turn-screen-off, so it shows the phone and powers the
        screen on.
        """
        cmd = ["scrcpy"] + list(resolved_target) + [
            "--window-title=" + UNLOCK_WINDOW_TITLE,
            "--no-audio",
            "--stay-awake",
            "--window-width=400",
        ]
        try:
            return subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            return None

    def wait_for_device(self, target_args, session_id, auto_unlock=True,
                        timeout=25.0, locked_timeout=90.0):
        """Hold the launch until the phone can actually serve it.

        An unreachable phone (adbd restarts on every unlock and takes a few seconds to come
        back) just fails. A phone on its lockscreen shows nothing worth mirroring. So: wait
        for it to answer, swipe the lockscreen away once, and when that is not enough (a PIN)
        put up a plain mirror window to type it in.

        Returns the resolved target to launch with, or None on timeout; the reason for a None
        is left in `wait_failures[session_id]`.
        """
        deadline = time.time() + timeout
        unlock_proc = None
        notified = False
        swiped = False
        locked = None
        self.wait_failures.pop(session_id, None)
        try:
            while True:
                resolved = self.resolve_adb_target(target_args)
                locked, secure = self.keyguard_state(resolved)
                if locked is True and auto_unlock and not swiped:
                    swiped = True
                    self._swipe_unlock(resolved)
                    # Unlocking restarts adbd: wait for it to answer again rather than start a
                    # scrcpy that dies a second later.
                    for _ in range(10):
                        time.sleep(0.25)
                        resolved = self.resolve_adb_target(target_args)
                        if self.keyguard_state(resolved)[0] is not None:
                            break
                    continue
                if locked is False:
                    return resolved
                if locked is True and not auto_unlock:
                    # Auto-unlock is off: a mirror of the lockscreen is what was asked for.
                    return resolved

                if locked is True and unlock_proc is None:
                    unlock_proc = self._spawn_unlock_helper(resolved)
                    if unlock_proc is not None:
                        # Unlocking is a human action: give it human time.
                        deadline = time.time() + locked_timeout
                    self.emit({
                        "event": "waiting",
                        "id": session_id,
                        "reason": "locked",
                        "unlockWindow": unlock_proc is not None,
                        # The PIN pad will be black in that window. Input still reaches the
                        # phone, so it can be typed blind: but only if the user knows.
                        "secure": bool(secure),
                    })
                    notified = True
                elif not notified:
                    notified = True
                    self.emit({
                        "event": "waiting",
                        "id": session_id,
                        "reason": "locked" if locked else "unreachable",
                    })

                # Closing the unlock window is how the user says "not now".
                if unlock_proc is not None and unlock_proc.poll() is not None:
                    self.wait_failures[session_id] = "unlock_closed"
                    return None
                if time.time() >= deadline:
                    self.wait_failures[session_id] = "locked" if locked else "unreachable"
                    return None
                time.sleep(1.0)
        finally:
            if unlock_proc is not None and unlock_proc.poll() is None:
                try:
                    unlock_proc.terminate()
                except Exception:
                    pass

    # -------------------------------------------------------------- sessions

    def launch_session(self, session_id, target_args, extra_args, auto_unlock=True):
        with self.lock:
            if session_id in self.starting:
                # A launch is already waiting for the phone. If a stop came in the meantime, this
                # launch cancels it and lets that one go on.
                self.deliberate.discard(session_id)
                return
            proc = self.processes.get(session_id)
            running = proc is not None and proc.poll() is None
            if not running:
                self.starting.add(session_id)
                self.deliberate.discard(session_id)
                self.keepalives[session_id] = time.time()

        if running:
            # Outside the lock: focus_session takes it too, and it is not re-entrant.
            self.focus_session(session_id)
            self.emit({"event": "started", "id": session_id, "pid": proc.pid,
                       "title": title_for(session_id), "alreadyRunning": True})
            return

        # The wait below can take seconds; keep stdin responsive meanwhile.
        threading.Thread(
            target=self._start_session,
            args=(session_id, target_args, extra_args, auto_unlock),
            daemon=True).start()

    def _start_session(self, session_id, target_args, extra_args, auto_unlock=True):
        args = list(extra_args or [])
        proc = None
        try:
            resolved_target = self.wait_for_device(target_args, session_id, auto_unlock=auto_unlock)
            with self.lock:
                # Stopped while it was waiting for the phone: nobody wants this session any more.
                cancelled = session_id in self.deliberate
                if cancelled:
                    self.deliberate.discard(session_id)
            if cancelled:
                return
            if resolved_target is None:
                reason = self.wait_failures.pop(session_id, "unreachable")
                self.emit({
                    "event": "error",
                    "id": session_id,
                    "reason": reason,
                    "message": {
                        "unlock_closed": "The unlock window was closed before the phone was unlocked",
                        "locked": "The phone stayed locked",
                    }.get(reason, "The phone is not reachable over ADB"),
                })
                return

            title = title_for(session_id)
            cmd = ["scrcpy"] + resolved_target + ["--window-title=" + title] + args
            proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                                    text=True, preexec_fn=_default_sigint)
            with self.lock:
                self.processes[session_id] = proc
                self.session_info[session_id] = {"id": session_id, "title": title, "pid": proc.pid}
            self.emit({"event": "started", "id": session_id, "pid": proc.pid, "title": title})
        except Exception as e:
            self.emit({"event": "error", "id": session_id,
                       "message": "Failed to launch scrcpy: %s" % e})
            return
        finally:
            with self.lock:
                self.starting.discard(session_id)

        self._wait_process(session_id, proc)

    def _wait_process(self, session_id, proc):
        # Drained as it comes, not read at the end: a pipe nobody reads fills up after 64 KB of
        # warnings, and scrcpy then blocks mid-session on its next log line. scrcpy follows the
        # line that says what went wrong with ones about tearing down, so the first ERROR is
        # the cause; the last line is only the fallback for a death that never said ERROR.
        err_msg = ""
        first_error = ""
        try:
            for line in proc.stderr:
                line = line.strip()
                if not line:
                    continue
                err_msg = line
                if not first_error and line.startswith("ERROR:"):
                    first_error = line[len("ERROR:"):].strip()
        except Exception:
            pass
        if first_error:
            err_msg = first_error
        code = proc.wait()

        with self.lock:
            # Whether the shell asked for this end: said in the event itself, because the shell may
            # already have started the next session (clearing what it remembers of the stop) by
            # the time this arrives, and would then read a stop as a crash.
            was_deliberate = session_id in self.deliberate
            self.processes.pop(session_id, None)
            self.session_info.pop(session_id, None)
            self.deliberate.discard(session_id)

        self.emit({"event": "exited", "id": session_id, "code": code, "error": err_msg,
                   "deliberate": was_deliberate})

    def stop_session(self, session_id):
        with self.lock:
            self.deliberate.add(session_id)
            proc = self.processes.get(session_id)
        if proc and proc.poll() is None:
            try:
                proc.terminate()
                time.sleep(0.1)
                if proc.poll() is None:
                    proc.kill()
            except Exception:
                pass

    def stop_all(self):
        with self.lock:
            ids = list(self.processes.keys())
        for session_id in ids:
            self.stop_session(session_id)

    def focus_session(self, session_id):
        with self.lock:
            info = self.session_info.get(session_id)
        if not info or not info.get("title"):
            return

        selector = "title:^{}$".format(info["title"])
        # Hyprland evaluates `hyprctl dispatch` as Lua when the config is a Lua file, and there
        # the classic `focuswindow <selector>` form is a syntax error. hyprctl still exits 0 in
        # that case, so the reply body is what says whether the dispatch took.
        #
        # Output is captured rather than inherited: this process' stdout is the JSON event
        # stream, and a stray hyprctl line corrupts it.
        for cmd in (
            ["hyprctl", "dispatch", "focuswindow", selector],
            ["hyprctl", "dispatch", 'hl.dsp.focus{window="' + selector + '"}'],
        ):
            try:
                res = subprocess.run(cmd, capture_output=True, text=True, timeout=3)
            except Exception:
                continue
            if res.returncode == 0 and res.stdout.strip().lower().startswith("ok"):
                return

    def note_keepalive(self, session_id):
        with self.lock:
            self.keepalives[session_id] = time.time()

    def _keepalive_watchdog(self):
        while self.running:
            time.sleep(5)
            now = time.time()
            with self.lock:
                stale = [sid for sid in self.SHELL_OWNED
                         if sid in self.processes
                         and self.processes[sid].poll() is None
                         and now - self.keepalives.get(sid, now) > self.KEEPALIVE_TIMEOUT]
            for sid in stale:
                self.stop_session(sid)

    def handle_line(self, line):
        line = line.strip()
        if not line:
            return
        try:
            msg = json.loads(line)
            cmd = msg.get("cmd")
            if cmd == "launch":
                self.launch_session(
                    session_id=msg.get("id"),
                    target_args=msg.get("target_args"),
                    extra_args=msg.get("extra_args"),
                    auto_unlock=bool(msg.get("auto_unlock", True)))
            elif cmd == "stop":
                self.stop_session(msg.get("id"))
            elif cmd == "stop_all":
                self.stop_all()
            elif cmd == "keepalive":
                self.note_keepalive(msg.get("id"))
            elif cmd == "focus":
                self.focus_session(msg.get("id"))
        except Exception as e:
            sys.stderr.write("Command parse error: %s\n" % e)

    def shutdown(self):
        with self.lock:
            owned = [proc for sid, proc in self.processes.items()
                     if sid in self.SHELL_OWNED and proc.poll() is None]
        for proc in owned:
            try:
                proc.terminate()
            except Exception:
                pass
        for proc in owned:
            try:
                proc.wait(timeout=2)
            except Exception:
                try:
                    proc.kill()
                except Exception:
                    pass

    def run(self):
        threading.Thread(target=self._keepalive_watchdog, daemon=True).start()
        try:
            for line in sys.stdin:
                self.handle_line(line)
                if not self.running:
                    break
        finally:
            self.shutdown()


def main():
    argparse.ArgumentParser(description="scrcpy session manager for the SekaiPop phone mirror").parse_args()

    manager = ScrcpySessionManager()

    # `setpriv --pdeathsig TERM` is what brings this process down with the shell, and the
    # default handler would exit before `finally` ran.
    def _terminate(_signum, _frame):
        manager.shutdown()
        sys.exit(0)

    signal.signal(signal.SIGTERM, _terminate)
    signal.signal(signal.SIGHUP, _terminate)

    manager.run()


if __name__ == "__main__":
    main()
