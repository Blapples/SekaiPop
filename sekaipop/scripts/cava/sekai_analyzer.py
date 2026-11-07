#!/usr/bin/env python3

import argparse
import json
import shutil
import signal
import subprocess
import sys
import time
from collections import deque

import numpy as np

try:
    import aubio as _aubio                                # optional
except Exception:                                         # noqa: BLE001 (missing, or built for another numpy)
    _aubio = None

SR = 44100
HOP = 735                       # 60 frames a second
NBANDS = 24
BAND_LO, BAND_HI = 40.0, 14000.0

LEAD_LO, LEAD_HI = 150.0, 1100.0     # fundamental range of the lead (voice, synth)
BASS_LO, BASS_HI = 44.0, 200.0
LEAD_CLARITY = 0.82                  # how periodic a tone must be to count as a lead (0..1)

# onset roles, as bins of the 1024-point spectrum (43 Hz each)
B_LOW = (1, 4)                  # 43..172 Hz         kick
B_BODY = (4, 15)                # 172..640 Hz        snare body
B_NOISE = (47, 210)             # 2..9 kHz           snare rattle
B_HAT = (163, 373)              # 7..16 kHz          hats
REFRACTORY = {"k": 0.12, "s": 0.12, "h": 0.06}


def band_edges():
    return BAND_LO * (BAND_HI / BAND_LO) ** (np.arange(NBANDS + 1) / NBANDS)


def clamp(x, lo, hi):
    return lo if x < lo else hi if x > hi else x


class RoleTracker:

    """Adaptive-threshold onset picking for one flux signal."""

    def __init__(self, floor, k=1.5, refractory=0.12):
        self.hist = deque(maxlen=60)
        self.floor = floor
        self.k = k
        self.refractory = refractory
        self.prev = 0.0
        self.peak = 0.0
        self.last = -1e9
        self.fired = False

    def update(self, flux, t):
        h = self.hist
        if len(h) >= 10:
            a = np.fromiter(h, float)
            thr = a.mean() + self.k * a.std() + self.floor
        else:
            thr = 1e9
        self.peak = max(self.peak * 0.994, flux)          # ~3 s to forget
        fire = (flux > thr and flux >= self.prev * 0.98
                and t - self.last >= self.refractory)
        self.prev = flux
        h.append(flux)
        self.fired = fire
        if not fire:
            return 0.0
        self.last = t
        return clamp(flux / max(self.peak, 1e-9), 0.05, 1.0)


def nsdf_pitch(y, fmin, fmax):
    """McLeod pitch method on a band-limited frame.

    Returns (hz, clarity) or (0, 0). clarity ~1 for a clean periodic tone, low
    for noise, drums and chords.
    """
    n = len(y)
    lmin = int(SR / fmax)
    lmax = min(int(SR / fmin), n // 2)
    e = float(np.dot(y, y))
    if e < 1e-12 or lmax <= lmin + 2:
        return 0.0, 0.0
    size = 1 << int(np.ceil(np.log2(2 * n)))
    f = np.fft.rfft(y, size)
    r = np.fft.irfft(f * np.conj(f), size)[: lmax + 2]
    sq = np.concatenate(([0.0], np.cumsum(y * y)))
    tau = np.arange(lmax + 2)
    m = (sq[n - tau] + (sq[n] - sq[tau]))                 # sum x_j^2 + x_{j+tau}^2
    nsdf = 2.0 * r / np.maximum(m, 1e-12)
    # the key maximum: highest peak, after the first dip below zero
    seg = nsdf[: lmax + 1]
    neg = np.nonzero(seg < 0)[0]
    if len(neg) == 0:
        return 0.0, 0.0
    start = max(int(neg[0]), lmin)
    if start >= lmax:
        return 0.0, 0.0
    mid = seg[start:lmax]
    is_peak = (mid > seg[start - 1:lmax - 1]) & (mid >= seg[start + 1:lmax + 1]) & (mid > 0)
    peaks = np.nonzero(is_peak)[0] + start
    if len(peaks) == 0:
        return 0.0, 0.0
    best = float(seg[peaks].max())
    # the first peak within 8 % of the best one: avoids picking a multiple of the period
    bi = int(peaks[np.nonzero(seg[peaks] >= 0.92 * best)[0][0]])
    a, b, c = seg[bi - 1], seg[bi], seg[min(bi + 1, lmax)]
    den = a - 2 * b + c
    off = 0.5 * (a - c) / den if den < -1e-12 else 0.0
    lag = bi + clamp(off, -0.5, 0.5)
    return SR / lag, clamp(float(b), 0.0, 1.0)


class Analyzer:
    def __init__(self, engine="auto"):
        self.engine = "numpy"
        self.engine_note = "numpy"
        self.aubio_ok = False
        if engine in ("auto", "aubio"):
            if _aubio is None:
                if engine == "aubio":
                    print("sekai-analyzer: python-aubio can't be imported, using numpy", file=sys.stderr)
            else:
                try:
                    self._init_aubio()
                    self.engine = "aubio"
                    self.engine_note = "aubio " + str(getattr(_aubio, "version", "?"))
                except Exception as e:                    # noqa: BLE001
                    print("sekai-analyzer: aubio failed to start (%s), using numpy" % e, file=sys.stderr)
        self.buf = np.zeros(4096, np.float32)
        self.hann1024 = np.hanning(1024).astype(np.float32)
        self.hann4096 = np.hanning(4096).astype(np.float32)
        edges = band_edges()
        f4 = np.fft.rfftfreq(4096, 1 / SR)
        self.band_idx = []
        for i in range(NBANDS):
            idx = np.nonzero((f4 >= edges[i]) & (f4 < edges[i + 1]))[0]
            if len(idx) == 0:
                idx = np.array([int(np.argmin(np.abs(f4 - (edges[i] + edges[i + 1]) / 2)))])
            self.band_idx.append(idx)
        centre = np.sqrt(edges[:-1] * edges[1:])
        self.tilt_db = 3.0 * np.log2(np.maximum(centre, 100.0) / 100.0)
        self.ref_db = -40.0
        self.peak = 0.05                                  # input amplitude follower
        self.prev_L = np.zeros(513, np.float32)
        self.trackers = {
            "k": RoleTracker(0.02, 1.0, REFRACTORY["k"]),
            "s": RoleTracker(0.05, 1.5, REFRACTORY["s"]),
            "h": RoleTracker(0.04, 1.4, REFRACTORY["h"]),
        }
        self.flux_follow = 0.05
        self.t = 0.0
        self.tick = 0
        self.last_v = None
        self.last_kick = -1.0
        self.last_snare = -1.0
        # lead tone
        self.lead_mask = None
        self.lead_hist = deque(maxlen=3)
        self.lead_last = (0.0, -1.0)                      # hz, time
        # bass note
        self.bass_hz = 0.0                                # the held bass pitch
        self.bass_cand = 0.0
        self.bass_cand_n = 0
        self.bass_gone = 0
        self.bass_t = -1.0

    # -- aubio ----------------------------------------------------------------

    def _init_aubio(self):
        def pitch(buf):
            p = _aubio.pitch("yinfft", buf, buf, SR)      # hop = buf: we hand it whole frames
            p.set_unit("Hz")
            p.set_silence(-90.0)
            return p
        self.ap_lead = pitch(2048)
        self.ap_bass = pitch(2048)
        self.at = _aubio.tempo("default", 1024, 512, SR)
        self.at_fifo = np.zeros(0, np.float32)
        self.at_samples = 0                               # fed so far, for "seconds ago"
        self.aubio_ok = True

    def _pitch(self, which, y, fmin, fmax):
        """(hz, clarity) of a band-limited frame, with aubio when it works."""
        if self.aubio_ok:
            try:
                p = self.ap_lead if which == "lead" else self.ap_bass
                hz = float(p(np.ascontiguousarray(y, dtype=np.float32))[0])
                conf = float(p.get_confidence())
                if hz < fmin or hz > fmax:
                    return 0.0, 0.0
                return hz, clamp(conf, 0.0, 1.0)
            except Exception as e:                        # noqa: BLE001
                print("sekai-analyzer: aubio pitch failed (%s), using numpy" % e, file=sys.stderr)
                self.aubio_ok = False
        return nsdf_pitch(y, fmin, fmax)

    def _beats(self, hop):
        """Feed aubio's beat tracker in its own 512-sample steps; the last beat in
        this hop as [bpm, confidence, seconds ago], or None."""
        if not self.aubio_ok:
            return None
        try:
            self.at_fifo = np.concatenate((self.at_fifo, hop.astype(np.float32)))
            beat = None
            while len(self.at_fifo) >= 512:
                chunk, self.at_fifo = self.at_fifo[:512], self.at_fifo[512:]
                self.at_samples += 512
                if self.at(chunk)[0]:
                    ago = (self.at_samples - float(self.at.get_last())) / SR
                    bpm = float(self.at.get_bpm())
                    if bpm > 0:
                        beat = [round(bpm, 1), round(clamp(float(self.at.get_confidence()), 0.0, 1.0), 2),
                                round(clamp(ago, 0.0, 0.5), 3)]
            return beat
        except Exception as e:                            # noqa: BLE001
            print("sekai-analyzer: aubio tempo failed (%s), ChartMath finds the beat" % e, file=sys.stderr)
            self.aubio_ok = False
            return None

    # -- helpers -------------------------------------------------------------

    def meters(self, x4096):
        spec = np.abs(np.fft.rfft(x4096 * self.hann4096)) / (len(x4096) / 4.0)
        out = np.zeros(NBANDS)
        for i, idx in enumerate(self.band_idx):
            out[i] = spec[idx].max()
        db = 20.0 * np.log10(out + 1e-7) + self.tilt_db
        top = float(db.max())
        self.ref_db = max(top, self.ref_db - 0.05)        # ~3 dB a second to forget
        rel = (db - (self.ref_db - 48.0)) / 48.0
        lv = np.clip(rel, 0.0, 1.0) ** 1.3
        return lv, spec

    def flux_bands(self, x1024):
        spec = np.abs(np.fft.rfft(x1024 * self.hann1024)) / 256.0
        L = np.log1p(300.0 * spec)
        pm = self.prev_L
        # compare against the previous frame's loudest neighbour: steady vibrato
        # and held tones then don't count as onsets
        ref = np.maximum(pm, np.maximum(np.concatenate(([0], pm[:-1])),
                                        np.concatenate((pm[1:], [0]))))
        rise = np.maximum(L - ref, 0.0)
        self.prev_L = L

        def band(b):
            return float(rise[b[0]:b[1]].mean())

        return band(B_LOW), band(B_BODY), band(B_NOISE), band(B_HAT)

    def band_signal(self, x, lo, hi):
        """The frame with only lo..hi Hz kept (rectangular window, FFT mask)."""
        n = len(x)
        f = np.fft.rfft(x)
        fr = np.fft.rfftfreq(n, 1 / SR)
        total = float(np.sum(np.abs(f) ** 2))
        f[(fr < lo) | (fr > hi)] = 0
        return np.fft.irfft(f, n), float(np.sum(np.abs(f) ** 2)), total

    # -- one hop -------------------------------------------------------------

    def process(self, hop):
        """hop: HOP float samples in -1..1. Returns the frame dict."""
        self.buf = np.concatenate((self.buf[HOP:], hop.astype(np.float32)))
        self.t += HOP / SR
        t = self.t
        amp = float(np.max(np.abs(hop))) if len(hop) else 0.0
        if amp < 1e-4:                                    # digital silence
            self.flux_follow *= 0.99
            self.last_v = None
            return {"b": [0] * NBANDS, "o": 0.0, "e": []}
        self.peak = max(self.peak * 0.9985, amp, 0.02)    # ~10 s
        x = self.buf / self.peak * 0.5

        lv, _ = self.meters(self.buf)
        low, body, noise, hat = self.flux_bands(x[-1024:])
        total = 1.25 * low + body + noise + 0.6 * hat
        self.flux_follow = max(self.flux_follow * 0.995, total, 0.02)
        events = []

        k = self.trackers["k"].update(low, t)
        s = self.trackers["s"].update(min(body, noise * 1.2), t)     # needs both
        h = self.trackers["h"].update(hat, t)
        if s > 0:
            events.append(["s", round(s, 2)])
            self.last_snare = t
        if k > 0:
            events.append(["k", round(k, 2)])
            self.last_kick = t
        # a hat right on a kick or snare is the same hit, not a second one
        if h > 0 and t - self.last_snare > 0.05 and t - self.last_kick > 0.04:
            events.append(["h", round(h, 2)])

        out = {"b": [int(v * 1000) for v in lv],
               "o": round(float(clamp(total / self.flux_follow, 0.0, 1.5)), 3),
               "e": events}

        beat = self._beats(hop)
        if beat:
            out["t"] = beat

        # The tone trackers are the expensive part and change slowly: every other frame.
        self.tick += 1
        if self.tick % 2:
            if self.last_v is not None:
                out["v"] = self.last_v
            return out
        # ===== lead tone =====
        frame = x[-2048:].astype(np.float32)
        y, e_lead, e_all = self.band_signal(frame, 130.0, 2500.0)
        ratio = e_lead / max(e_all, 1e-12)
        hz, clar = self._pitch("lead", y, LEAD_LO, LEAD_HI)
        ok = hz > 0 and clar >= LEAD_CLARITY and ratio >= 0.12 and e_all > 1e-3
        if ok:
            # octave errors: stay on the octave nearest to the last pitch
            lh, lt = self.lead_last
            if lh > 0 and t - lt < 0.1:
                for mult in (2.0, 0.5):
                    if abs(np.log2(hz * mult / lh)) < 0.1:
                        hz *= mult
                        break
            self.lead_hist.append(hz)
            med = float(np.median(self.lead_hist))
            self.lead_last = (med, t)
            pos = clamp(np.log2(med / LEAD_LO) / np.log2(LEAD_HI / LEAD_LO), 0.0, 1.0)
            out["v"] = [round(float(pos), 3), round(clar, 2)]
            self.last_v = out["v"]
        else:
            self.lead_hist.clear()
            self.last_v = None

        # ===== bass notes =====
        yb, e_b, e_all_b = self.band_signal(x[-2048:], 35.0, 260.0)
        bhz, bclar = self._pitch("bass", yb, BASS_LO, BASS_HI)
        b_ok = bhz > 0 and bclar >= 0.85 and e_b / max(e_all_b, 1e-12) >= 0.25
        if b_ok:
            self.bass_gone = 0
            if self.bass_cand > 0 and abs(12 * np.log2(bhz / self.bass_cand)) < 0.7:
                self.bass_cand_n += 1
            else:
                self.bass_cand, self.bass_cand_n = bhz, 1
            if self.bass_cand_n >= 2:
                moved = (self.bass_hz == 0
                         or abs(12 * np.log2(self.bass_cand / self.bass_hz)) >= 0.8)
                if moved and t - self.bass_t > 0.08:
                    pos = clamp(np.log2(self.bass_cand / BASS_LO) / np.log2(BASS_HI / BASS_LO), 0.0, 1.0)
                    events.append(["b", round(clamp(e_b / max(e_all_b, 1e-12), 0.2, 1.0), 2),
                                   round(float(pos), 3)])
                    self.bass_hz = self.bass_cand
                    self.bass_t = t
        else:
            self.bass_gone += 1
            self.bass_cand_n = 0
            if self.bass_gone > 9:                         # ~150 ms without a tone: the next one is new
                self.bass_hz = 0.0
        return out


# ===== input =====

def open_capture():
    """Start a capture of the default output's monitor, 44.1 kHz mono s16le."""
    attempts = []
    if shutil.which("parec"):
        attempts.append(["parec", "--device=@DEFAULT_MONITOR@", "--format=s16le",
                         "--rate=%d" % SR, "--channels=1", "--latency-msec=32"])
    if shutil.which("pw-record"):
        attempts.append(["pw-record", "-P", "stream.capture.sink=true", "--format", "s16",
                         "--rate", str(SR), "--channels", "1", "-"])
    if not attempts:
        raise RuntimeError("neither parec (pipewire-pulse / pulseaudio-utils) nor pw-record found")
    return subprocess.Popen(attempts[0], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)


def read_exact(stream, n):
    data = b""
    while len(data) < n:
        chunk = stream.read(n - len(data))
        if not chunk:
            return None
        data += chunk
    return data


def skip_wav_header(stream):
    """pw-record may write a WAV header even to stdout; skip it if there is one."""
    head = read_exact(stream, 4)
    if head is None:
        return None
    if head != b"RIFF":
        return head                                       # raw audio: these were samples
    read_exact(stream, 4)
    read_exact(stream, 4)                                 # "WAVE"
    while True:
        cid = read_exact(stream, 4)
        size = read_exact(stream, 4)
        if cid is None or size is None:
            return None
        n = int.from_bytes(size, "little")
        if cid == b"data":
            return b""
        read_exact(stream, n + (n & 1))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file")
    ap.add_argument("--realtime", action="store_true")
    ap.add_argument("--engine", choices=("auto", "aubio", "numpy"), default="auto")
    args = ap.parse_args()

    # The shell stops us with SIGTERM: leave quietly and take the capture with us.
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))

    an = Analyzer(args.engine)
    print("sekai-analyzer: engine %s" % an.engine_note, file=sys.stderr, flush=True)
    out = sys.stdout
    nbytes = HOP * 2
    frames = 0
    t0 = time.monotonic()
    proc = None
    try:
        while True:
            if args.file:
                stream = open(args.file, "rb")
            else:
                try:
                    proc = open_capture()
                except Exception as e:                    # noqa: BLE001
                    print("sekai-analyzer: %s" % e, file=sys.stderr)
                    return 3
                stream = proc.stdout
            pending = skip_wav_header(stream)
            if pending is not None:
                while True:
                    data = read_exact(stream, nbytes - len(pending))
                    if data is None:
                        break
                    data = pending + data
                    pending = b""
                    samples = np.frombuffer(data, dtype="<i2").astype(np.float32) / 32768.0
                    out.write(json.dumps(an.process(samples), separators=(",", ":")) + "\n")
                    out.flush()
                    frames += 1
                    if args.realtime:
                        lag = t0 + frames * HOP / SR - time.monotonic()
                        if lag > 0:
                            time.sleep(lag)
            if args.file:
                return 0
            # The capture ended. Never delivered anything: it can't work here.
            # Otherwise (the sound server restarted, say) try again shortly.
            if frames == 0:
                print("sekai-analyzer: the audio capture gave no data", file=sys.stderr)
                return 4
            proc.terminate()
            time.sleep(1.0)
    except (BrokenPipeError, KeyboardInterrupt):
        return 0
    finally:
        if proc is not None:
            try:
                proc.terminate()
            except Exception:                             # noqa: BLE001
                pass


if __name__ == "__main__":
    sys.exit(main())
