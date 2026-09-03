#!/usr/bin/env python3
"""Generate procedural WAV sound effects for life-after-death.

Creates simple but distinct SFX using basic waveform synthesis.
Outputs to assets/audio/sfx/
"""
import wave
import struct
import os
import numpy as np

SAMPLE_RATE = 44100
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "sfx")


def write_wav(path: str, samples: np.ndarray) -> None:
    """Write mono 16-bit WAV."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # Normalize to prevent clipping
    max_val = np.max(np.abs(samples)) if samples.size > 0 else 1.0
    if max_val > 1.0:
        samples = samples / max_val
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        data = (samples * 32767).astype(np.int16).tobytes()
        wf.writeframes(data)


def gunshot() -> np.ndarray:
    """Short percussive burst: filtered noise with fast decay."""
    duration = 0.15  # 150ms
    n = int(SAMPLE_RATE * duration)
    t = np.arange(n) / SAMPLE_RATE
    i = np.arange(n)
    
    # Exponential decay envelope
    env = np.exp(-t * 40)
    # Bandpass-ish noise: mix of low and high freq noise
    noise = (np.sin(t * 2000 + i * 0.7) + np.sin(t * 8000 + i * 1.3)) * 0.5
    # Add a "pop" at the start
    pop = np.sin(t * 120) * np.exp(-t * 80) * 0.3
    
    return (noise * 0.7 + pop * 0.3) * env


def reload_sound() -> np.ndarray:
    """Mechanical click-chamber: two sharp clicks with metallic ring."""
    duration = 0.6
    n = int(SAMPLE_RATE * duration)
    t = np.arange(n) / SAMPLE_RATE
    samples = np.zeros(n)
    
    # First click at 0.05s
    mask1 = (t > 0.05) & (t < 0.08)
    dt1 = t[mask1] - 0.05
    env1 = np.exp(-dt1 * 100)
    samples[mask1] += (np.sin(dt1 * 800) + np.sin(dt1 * 2400) * 0.3) * env1 * 0.5
    
    # Second click at 0.25s
    mask2 = (t > 0.25) & (t < 0.29)
    dt2 = t[mask2] - 0.25
    env2 = np.exp(-dt2 * 80)
    samples[mask2] += (np.sin(dt2 * 600) + np.sin(dt2 * 1800) * 0.4) * env2 * 0.6
    
    # Metallic ring tail
    mask3 = t > 0.3
    dt3 = t[mask3] - 0.3
    env3 = np.exp(-dt3 * 15)
    samples[mask3] += np.sin(dt3 * 1200) * env3 * 0.15
    samples[mask3] += np.sin(dt3 * 2800) * env3 * 0.08
    
    return samples


def player_hurt() -> np.ndarray:
    """Short grunt/impact: low freq thud + brief vocal formant."""
    duration = 0.35
    n = int(SAMPLE_RATE * duration)
    t = np.arange(n) / SAMPLE_RATE
    i = np.arange(n)
    
    env = np.exp(-t * 12)
    # Thud
    thud = np.sin(t * 80) * env * 0.6
    # Vocal-ish formant sweep
    freq = 200 + 150 * np.exp(-t * 8)
    vocal = np.sin(2 * np.pi * freq * t) * env * 0.3
    # Breath noise
    breath = (np.sin(t * 4000 + i * 0.9) * 0.5) * np.exp(-t * 20) * 0.2
    
    return thud + vocal + breath


def zombie_hit() -> np.ndarray:
    """Wet impact/squish: noisy burst with low freq thump."""
    duration = 0.2
    n = int(SAMPLE_RATE * duration)
    t = np.arange(n) / SAMPLE_RATE
    i = np.arange(n)
    
    env = np.exp(-t * 30)
    # Low thump
    thump = np.sin(t * 60) * env * 0.5
    # Wet noise
    wet = (np.sin(t * 1200 + i * 1.1) + np.sin(t * 3500 + i * 0.7)) * 0.5 * env * 0.4
    # Squish
    squish = np.sin(t * 180) * np.exp(-t * 50) * 0.3
    
    return thump + wet + squish


def zombie_death() -> np.ndarray:
    """Longer groan/death rattle: descending formant + rattle tail."""
    duration = 1.0
    n = int(SAMPLE_RATE * duration)
    t = np.arange(n) / SAMPLE_RATE
    i = np.arange(n)
    
    # Groan: descending pitch
    groan_env = np.exp(-t * 1.5)
    freq = 180 * np.exp(-t * 1.2) + 60
    groan = np.sin(2 * np.pi * freq * t) * groan_env * 0.4
    # Formant emphasis
    formant = np.sin(2 * np.pi * (freq * 2.5) * t) * groan_env * 0.15
    
    # Rattle/breath noise in second half
    rattle = np.zeros(n)
    mask = t > 0.4
    rt = t[mask] - 0.4
    i_mask = i[mask]
    rattle_env = np.exp(-rt * 3)
    rattle[mask] = (np.sin(rt * 80 + i_mask * 1.5) * 0.3 + np.sin(rt * 4000 + i_mask * 0.9) * 0.7) * rattle_env * 0.25
    
    return groan + formant + rattle

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