"""Generate the app's earcon / alert WAV assets.

Produces three 44.1 kHz 16-bit mono PCM files in assets/alerts/:

  listen_start.wav  Rising two-note chime (G5 -> C6). Plays on push-to-talk
                    press, BEFORE the mic opens: "I'm listening."
  listen_stop.wav   Falling two-note chime (C6 -> G5). Plays after release
                    once capture has been torn down: "Got it, processing."
  alert.wav         Urgent alternating dual-tone alarm for the CRITICAL
                    obstacle state (referenced by home_screen.dart but the
                    asset was missing until now).

Each note is a sine fundamental with soft 2nd/3rd harmonics (glassy,
marimba-like — pleasant, not buzzy) shaped by a fast attack and an
exponential decay so there are no clicks at either end.
"""

import math
import struct
import wave
from pathlib import Path

SR = 44100
OUT = Path(r"d:\Thesis\Thesis_project\Test_app\test_app_1\assets\alerts")


def note(freq, dur_s, amp, attack_s=0.006, decay_tau=0.060,
         harmonics=((1, 1.0), (2, 0.35), (3, 0.12))):
    """One chime note: additive sines, linear attack, exponential decay."""
    n = int(SR * dur_s)
    out = [0.0] * n
    for i in range(n):
        t = i / SR
        env = min(t / attack_s, 1.0) * math.exp(-max(t - attack_s, 0.0) / decay_tau)
        s = sum(w * math.sin(2 * math.pi * freq * h * t) for h, w in harmonics)
        out[i] = amp * env * s
    return out


def mix(buf, samples, at_s):
    off = int(SR * at_s)
    need = off + len(samples)
    if len(buf) < need:
        buf.extend([0.0] * (need - len(buf)))
    for i, s in enumerate(samples):
        buf[off + i] += s


def write_wav(path, buf, peak):
    m = max(abs(s) for s in buf) or 1.0
    scale = peak / m
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for s in buf:
            v = int(max(-1.0, min(1.0, s * scale)) * 32767)
            frames += struct.pack("<h", v)
        w.writeframes(bytes(frames))
    print(f"wrote {path.name}: {len(buf) / SR:.3f}s peak={peak}")


# Loudness note: peaks near full scale and heavier 2nd/3rd harmonics push the
# energy into 1.5–5 kHz — the band where tiny phone speakers are most
# efficient and human hearing most sensitive — so the cues survive Dhaka
# street noise. Media volume is separately pinned to max by MainActivity.
LOUD = ((1, 1.0), (2, 0.55), (3, 0.20))

# listen_start: rising G5 -> C6, second note slightly stronger — an upward,
# questioning gesture: "yes? I'm listening." Kept SHORT (~0.2 s): the app
# holds the microphone closed until this chime finishes (playback overlapping
# capture start breaks the record stream on some devices), so every extra
# millisecond here delays the mic. If the length changes, update
# EarconService.startChimeLength to match.
buf = []
mix(buf, note(783.99, 0.09, 0.80, decay_tau=0.045, harmonics=LOUD), 0.000)
mix(buf, note(1046.50, 0.13, 1.00, decay_tau=0.055, harmonics=LOUD), 0.070)
write_wav(OUT / "listen_start.wav", buf, peak=0.92)

# listen_stop: falling C6 -> G5, quicker — a settling, closing gesture:
# "received."
buf = []
mix(buf, note(1046.50, 0.12, 0.90, harmonics=LOUD), 0.000)
mix(buf, note(783.99, 0.20, 0.80, decay_tau=0.075, harmonics=LOUD), 0.095)
write_wav(OUT / "listen_stop.wav", buf, peak=0.80)

# alert: CRITICAL alarm — fourteen 110 ms pulses alternating 950/1350 Hz with
# 55 ms gaps (~2.3 s). Dense harmonics (energy up to ~5.4 kHz) give it enough
# edge to cut through traffic without square-wave harshness.
buf = []
t = 0.0
for k in range(14):
    f = 950.0 if k % 2 == 0 else 1350.0
    mix(buf, note(f, 0.11, 1.0, attack_s=0.004, decay_tau=0.30,
                  harmonics=((1, 1.0), (2, 0.80), (3, 0.50),
                             (4, 0.25), (5, 0.12))), t)
    t += 0.165
write_wav(OUT / "alert.wav", buf, peak=0.98)
