#!/usr/bin/env python3
"""The phone mirror's session manager (scripts/phone/scrcpy_session_manager.py), run for real
against stand-in `adb` and `scrcpy` programs, so no phone is needed.

Run: python3 tests/phone-mirror-test/manager_unit.py
"""
import json, os, select, stat, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
MANAGER = os.path.join(HERE, "..", "..", "scripts", "phone", "scrcpy_session_manager.py")

ADB = """#!/bin/sh
case "$*" in
  *devices*) printf 'List of devices attached\\nFAKE123\\tdevice usb:1 model:Fake_Phone\\n' ;;
  *"dumpsys window"*) printf 'showing=false\\n' ;;
esac
"""
SCRCPY = """#!/bin/sh
trap 'exit 143' TERM
echo "INFO: fake scrcpy $*" >&2
while true; do sleep 0.2; done
"""

tmp = tempfile.mkdtemp()
for name, body in (("adb", ADB), ("scrcpy", SCRCPY)):
    path = os.path.join(tmp, name)
    open(path, "w").write(body)
    os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC)

env = dict(os.environ, PATH=tmp + ":" + os.environ["PATH"])
proc = subprocess.Popen([sys.executable, MANAGER], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        text=True, env=env)
checks = 0


def send(obj):
    proc.stdin.write(json.dumps(obj) + "\n")
    proc.stdin.flush()


def read(timeout=6):
    end = time.time() + timeout
    while time.time() < end:
        ready, _, _ = select.select([proc.stdout], [], [], 0.2)
        if ready:
            line = proc.stdout.readline()
            if line:
                return json.loads(line)
    return None


def check(cond, what):
    global checks
    assert cond, what
    checks += 1


LAUNCH = {"cmd": "launch", "id": "embed", "target_args": ["-s", "FAKE123"],
          "extra_args": ["--no-audio"], "auto_unlock": True}
STOP = {"cmd": "stop", "id": "embed"}

send(LAUNCH)
e = read()
check(e and e["event"] == "started" and e["title"] == "sekai-phone-embed", "a launch starts the session under its title")

send(STOP)
e = read()
check(e and e["event"] == "exited" and e["deliberate"] is True, "a stop is reported as asked for, not as a crash")

# Stop, then launch at once, while the first launch is still waiting for the phone: the launch wins.
send(LAUNCH); send(STOP); send(LAUNCH)
e = read(8)
check(e and e["event"] == "started", "a launch right after a stop is kept")
send(STOP)
e = read()
check(e and e["event"] == "exited" and e["deliberate"] is True, "and ends as asked")

# A stop that arrives while the launch still waits cancels it: nothing starts.
send(LAUNCH); send(STOP)
check(read(4) is None, "a stop during the wait cancels the launch")

proc.stdin.close()
proc.wait(timeout=5)
check(proc.returncode == 0, "the manager ends when the shell goes")
print("manager_unit: %d checks passed" % checks)
