#!/usr/bin/env python3
"""Generate the placeholder ambience beds and one-shot SFX.

    tools/gen_placeholder_audio.py

Why this exists. PLAN M10 wants CC0 packs, and the music candidates ARE real CC0
downloads (see CREDITS.md). The beds and the ten one-shots are synthesised here
instead, for the same reason the keeper sprites and item icons are drawn in code:
the game needs something in every slot before it is worth an author's afternoon
choosing between real ones, and a slot that is silent is a slot nobody notices is
empty. Everything here is ours, so it is CC0 by construction and carries no
attribution debt.

These are PLACEHOLDERS and are meant to be replaced. ASSET_MANIFEST.md lists
every one with its path, and the paths are stable so replacement is drop-in.

WAV rather than OGG because there is no encoder on this machine (no ffmpeg, no
oggenc, no sox) and Godot imports WAV natively. Beds loop; one-shots do not.

Nothing here is a feel value: levels live on the buses and the settings sliders,
and this script never touches them. (NEXT.md 2026-07-31.2 item 5.)
"""
import math
import os
import random
import struct
import wave

RATE = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot", "assets", "audio")

# One generator, one seed. Re-running must produce byte-identical files or every
# run shows up as a diff and the repo grows a new copy of the same noise.
SEED = 20260731


def write_wav(path, samples):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    frames = bytearray()
    for s in samples:
        v = int(max(-1.0, min(1.0, s)) * 32767)
        frames += struct.pack("<h", v)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(bytes(frames))
    print(f"  {os.path.relpath(path, os.path.join(ROOT, '..', '..'))}  {len(samples)/RATE:.1f}s")


def fade_edges(buf, ms=250):
    """Taper both ends so a looping bed has no click at the seam."""
    n = int(RATE * ms / 1000)
    for i in range(min(n, len(buf) // 2)):
        k = i / n
        buf[i] *= k
        buf[-1 - i] *= k
    return buf


def lowpass(buf, alpha):
    out, prev = [], 0.0
    for s in buf:
        prev += alpha * (s - prev)
        out.append(prev)
    return out


# --- ambience beds (loop) ---------------------------------------------------

def bed_sea(seconds=12.0):
    """Swell plus gulls. LOW tide: the shore is open and it sounds like it."""
    rng = random.Random(SEED + 1)
    n = int(RATE * seconds)
    surf = lowpass([rng.uniform(-1, 1) for _ in range(n)], 0.012)
    out = []
    for i, s in enumerate(surf):
        t = i / RATE
        # Two slow swells at different rates so the loop point is hard to hear.
        swell = 0.55 + 0.45 * math.sin(2 * math.pi * t / 7.0) * math.sin(2 * math.pi * t / 4.3)
        out.append(s * 6.0 * swell * 0.45)
    for _ in range(5):  # a few distant gulls
        at = rng.uniform(0.1, seconds - 1.2)
        f = rng.uniform(900, 1500)
        dur = rng.uniform(0.16, 0.3)
        for i in range(int(dur * RATE)):
            k = i / (dur * RATE)
            env = math.sin(math.pi * k) ** 2
            idx = int(at * RATE) + i
            if idx < n:
                out[idx] += 0.10 * env * math.sin(2 * math.pi * f * (1 + 0.35 * k) * i / RATE)
    return fade_edges(out)


def bed_wind(seconds=12.0):
    """MID/HIGH: the water is up, the shore is closing, the wind has the place."""
    rng = random.Random(SEED + 2)
    n = int(RATE * seconds)
    base = lowpass([rng.uniform(-1, 1) for _ in range(n)], 0.05)
    base = lowpass(base, 0.05)
    out = []
    for i, s in enumerate(base):
        t = i / RATE
        gust = 0.5 + 0.5 * math.sin(2 * math.pi * t / 5.5 + 0.7)
        out.append(s * 9.0 * (0.35 + 0.65 * gust) * 0.4)
    return fade_edges(out)


def bed_hearth(seconds=12.0):
    """Inside the tower with the fire lit. The one warm bed."""
    rng = random.Random(SEED + 3)
    n = int(RATE * seconds)
    body = lowpass([rng.uniform(-1, 1) for _ in range(n)], 0.02)
    out = [s * 3.0 * 0.22 for s in body]
    for _ in range(int(seconds * 11)):  # crackles
        at = int(rng.uniform(0, seconds - 0.05) * RATE)
        dur = int(rng.uniform(0.004, 0.02) * RATE)
        amp = rng.uniform(0.06, 0.3)
        for i in range(dur):
            if at + i < n:
                out[at + i] += amp * (1 - i / dur) * rng.uniform(-1, 1)
    return fade_edges(out)


# --- one-shots --------------------------------------------------------------

def tone(freq, dur, amp=0.32, shape="sine", sweep=1.0, seed=0):
    rng = random.Random(SEED + seed)
    n = int(RATE * dur)
    out = []
    for i in range(n):
        k = i / n
        env = math.sin(math.pi * k) ** 0.7
        f = freq * (1 + (sweep - 1) * k)
        if shape == "noise":
            v = rng.uniform(-1, 1)
        else:
            v = math.sin(2 * math.pi * f * i / RATE)
        out.append(amp * env * v)
    return out


def mix(*parts):
    n = max(len(p) for p in parts)
    out = [0.0] * n
    for p in parts:
        for i, s in enumerate(p):
            out[i] += s
    return out


ONE_SHOTS = {
    # id: (builder, human note for ASSET_MANIFEST)
    "gather":     lambda: mix(tone(420, 0.13, 0.20, "noise", seed=11), tone(660, 0.12, 0.14, sweep=1.2, seed=12)),
    "craft":      lambda: mix(tone(300, 0.20, 0.22, seed=13), tone(450, 0.18, 0.16, sweep=1.15, seed=14)),
    "place":      lambda: mix(tone(200, 0.16, 0.26, seed=15), tone(120, 0.12, 0.18, "noise", seed=16)),
    "milestone":  lambda: mix(tone(523, 0.5, 0.20, seed=17), tone(784, 0.45, 0.14, seed=18), tone(1046, 0.4, 0.09, seed=19)),
    "bottle_open": lambda: mix(tone(700, 0.18, 0.16, sweep=0.7, seed=20), tone(240, 0.2, 0.14, "noise", seed=21)),
    "page_turn":  lambda: tone(1200, 0.12, 0.13, "noise", seed=22),
    "radial_tick": lambda: tone(1500, 0.045, 0.14, seed=23),
    "tandem_ready": lambda: mix(tone(587, 0.35, 0.17, seed=24), tone(880, 0.35, 0.13, sweep=1.05, seed=25)),
    "beam":       lambda: mix(tone(180, 1.1, 0.24, sweep=2.4, seed=26), tone(90, 1.2, 0.18, "noise", seed=27)),
    "caught":     lambda: mix(tone(300, 0.4, 0.20, "noise", seed=28), tone(220, 0.35, 0.15, sweep=0.6, seed=29)),
}

BEDS = {"sea": bed_sea, "wind": bed_wind, "hearth": bed_hearth}


def main():
    print("ambience beds (looping):")
    for name, fn in BEDS.items():
        write_wav(os.path.join(ROOT, "ambience", f"{name}.wav"), fn())
    print("one-shots:")
    for name, fn in sorted(ONE_SHOTS.items()):
        write_wav(os.path.join(ROOT, "sfx", f"{name}.wav"), fn())
    print(f"\n{len(BEDS)} beds + {len(ONE_SHOTS)} one-shots. All CC0 (generated here).")


if __name__ == "__main__":
    main()
