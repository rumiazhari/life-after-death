#!/usr/bin/env python3
"""Generate procedural WAV sound effects for life-after-death.

Creates simple but distinct SFX using basic waveform synthesis.
Outputs to assets/audio/sfx/
"""
import wave
import struct
import math
import os

SAMPLE_RATE = 44100
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "sfx")

def write_wav(path: str, samples: list[float]) -> None:
    """Write mono 16-bit WAV."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # Normalize to prevent clipping
    max_val = max(abs(s) for s in samples) if samples else 1.0
    if max_val > 1.0:
        samples = [s / max_val for s in samples]
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        data = struct.pack(f"<{len(samples)}h", *[int(s * 32767) for s in samples])
        wf.writeframes(data)

def gunshot() -> list[float]:
    """Short percussive burst: filtered noise with fast decay."""
    duration = 0.15  # 150ms
    n = int(SAMPLE_RATE * duration)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        # Exponential decay envelope
        env = math.exp(-t * 40)
        # Bandpass-ish noise: mix of low and high freq noise
        noise = (math.sin(t * 2000 + i * 0.7) + math.sin(t * 8000 + i * 1.3)) * 0.5
        # Add a "pop" at the start
        pop = math.sin(t * 120) * math.exp(-t * 80) * 0.3
        samples.append((noise * 0.7 + pop * 0.3) * env)
    return samples

def reload_sound() -> list[float]:
    """Mechanical click-chamber: two sharp clicks with metallic ring."""
    duration = 0.6
    n = int(SAMPLE_RATE * duration)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        s = 0.0
        # First click at 0.05s
        if t > 0.05:
            dt = t - 0.05
            if dt < 0.03:
                env = math.exp(-dt * 100)
                s += (math.sin(dt * 800) + math.sin(dt * 2400) * 0.3) * env * 0.5
        # Second click at 0.25s
        if t > 0.25:
            dt = t - 0.25
            if dt < 0.04:
                env = math.exp(-dt * 80)
                s += (math.sin(dt * 600) + math.sin(dt * 1800) * 0.4) * env * 0.6
        # Metallic ring tail
        if t > 0.3:
            dt = t - 0.3
            env = math.exp(-dt * 15)
            s += math.sin(dt * 1200) * env * 0.15
            s += math.sin(dt * 2800) * env * 0.08
        samples.append(s)
    return samples

def player_hurt() -> list[float]:
    """Short grunt/impact: low freq thud + brief vocal formant."""
    duration = 0.35
    n = int(SAMPLE_RATE * duration)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = math.exp(-t * 12)
        # Thud
        thud = math.sin(t * 80) * env * 0.6
        # Vocal-ish formant sweep
        freq = 200 + 150 * math.exp(-t * 8)
        vocal = math.sin(2 * math.pi * freq * t) * env * 0.3
        # Breath noise
        breath = (math.sin(t * 4000 + i * 0.9) * 0.5) * math.exp(-t * 20) * 0.2
        samples.append(thud + vocal + breath)
    return samples

def zombie_hit() -> list[float]:
    """Wet impact/squish: noisy burst with low freq thump."""
    duration = 0.2
    n = int(SAMPLE_RATE * duration)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = math.exp(-t * 30)
        # Low thump
        thump = math.sin(t * 60) * env * 0.5
        # Wet noise
        wet = (math.sin(t * 1200 + i * 1.1) + math.sin(t * 3500 + i * 0.7)) * 0.5 * env * 0.4
        # Squish
        squish = math.sin(t * 180) * math.exp(-t * 50) * 0.3
        samples.append(thump + wet + squish)
    return samples

def zombie_death() -> list[float]:
    """Longer groan/death rattle: descending formant + rattle tail."""
    duration = 1.0
    n = int(SAMPLE_RATE * duration)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        # Groan: descending pitch
        groan_env = math.exp(-t * 1.5)
        freq = 180 * math.exp(-t * 1.2) + 60
        groan = math.sin(2 * math.pi * freq * t) * groan_env * 0.4
        # Formant emphasis
        formant = math.sin(2 * math.pi * (freq * 2.5) * t) * groan_env * 0.15
        # Rattle/breath noise in second half
        rattle = 0.0
        if t > 0.4:
            rt = t - 0.4
            rattle_env = math.exp(-rt * 3)
            rattle = (math.sin(rt * 80 + i * 1.5) * 0.3 + math.sin(rt * 4000 + i * 0.9) * 0.7) * rattle_env * 0.25
        samples.append(groan + formant + rattle)
    return samples

def main():
    print(f"Generating SFX to {OUTPUT_DIR}")
    write_wav(os.path.join(OUTPUT_DIR, "gunshot.wav"), gunshot())
    print("  gunshot.wav")
    write_wav(os.path.join(OUTPUT_DIR, "reload.wav"), reload_sound())
    print("  reload.wav")
    write_wav(os.path.join(OUTPUT_DIR, "player_hurt.wav"), player_hurt())
    print("  player_hurt.wav")
    write_wav(os.path.join(OUTPUT_DIR, "zombie_hit.wav"), zombie_hit())
    print("  zombie_hit.wav")
    write_wav(os.path.join(OUTPUT_DIR, "zombie_death.wav"), zombie_death())
    print("  zombie_death.wav")
    print("Done.")

if __name__ == "__main__":
    main()