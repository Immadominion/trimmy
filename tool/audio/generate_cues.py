#!/usr/bin/env python3
"""Rebuild Trimmy's original, sample-free sound cues using Python's stdlib.

Usage from any directory: python3 trimmy/tool/audio/generate_cues.py
Writes mono PCM16 / 48 kHz WAV files and a provenance/checksum manifest.
These are audition candidates; generated files have not been listening-approved.
"""

from __future__ import annotations

import hashlib
import json
import math
import random
import struct
import wave
from pathlib import Path


RATE = 48_000
SEED = 0x5452494D
PROJECT = Path(__file__).resolve().parents[2]
OUTPUT = PROJECT / "apps/mobile/assets/audio"


def fade(t: float, duration: float, attack: float, release: float) -> float:
    """Raised-cosine edges prevent hard sample discontinuities."""
    rise = 0.5 - 0.5 * math.cos(math.pi * min(1.0, max(0.0, t / attack)))
    fall = 0.5 - 0.5 * math.cos(
        math.pi * min(1.0, max(0.0, (duration - t) / release))
    )
    return rise * fall


def soft_tap() -> tuple[list[float], str]:
    duration = 0.085
    samples = []
    for i in range(round(RATE * duration)):
        t = i / RATE
        # A short woody body with soft, non-metallic higher partials.
        phase = 2 * math.pi * (345 * t - 155 * t * t)
        body = math.sin(phase) + 0.18 * math.sin(2.15 * phase)
        samples.append(body * math.exp(-t * 62) * fade(t, duration, 0.004, 0.022))
    return samples, "Original damped additive oscillator; quiet wooden tap."


def paper_open() -> tuple[list[float], str]:
    duration = 0.29
    rng = random.Random(SEED)
    samples = []
    low = 0.0
    slower = 0.0
    for i in range(round(RATE * duration)):
        t = i / RATE
        noise = rng.uniform(-1.0, 1.0)
        low += 0.19 * (noise - low)
        slower += 0.035 * (low - slower)
        filtered = low - slower
        # Two smooth small rustles suggest paper moving and settling.
        rustle = math.exp(-((t - 0.080) / 0.044) ** 2)
        rustle += 0.46 * math.exp(-((t - 0.192) / 0.039) ** 2)
        samples.append(filtered * rustle * fade(t, duration, 0.025, 0.040))
    return samples, "Original seeded filtered noise; two soft paper rustles."


def arrival() -> tuple[list[float], str]:
    duration = 0.53
    samples = []
    for i in range(round(RATE * duration)):
        t = i / RATE
        result = 0.0
        # Open fifth D5/A5, muted like felted keys; no cash-register sample.
        for onset, hz, gain in ((0.0, 587.3295, 1.0), (0.155, 880.0, 0.82)):
            age = t - onset
            if age < 0:
                continue
            note_length = duration - onset
            phase = 2 * math.pi * hz * age
            tone = math.sin(phase) + 0.10 * math.sin(2 * phase)
            result += gain * tone * math.exp(-age * 10.5) * fade(
                age, note_length, 0.012, 0.060
            )
        samples.append(result)
    return samples, "Original additive D5/A5 felted two-note arrival cue."


def write_cue(name: str, values: list[float], target_peak_dbfs: float) -> dict:
    # Remove the tiny DC bias of the finite noise waveform, then re-fade edges.
    mean = sum(values) / len(values)
    duration = len(values) / RATE
    clean = [
        (value - mean) * fade(i / RATE, duration, 0.002, 0.008)
        for i, value in enumerate(values)
    ]
    peak = max(abs(value) for value in clean)
    scale = (10 ** (target_peak_dbfs / 20)) / max(peak, 1e-12)
    pcm = [round(max(-1.0, min(1.0, value * scale)) * 32767) for value in clean]
    destination = OUTPUT / f"{name}.wav"
    with wave.open(str(destination), "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(RATE)
        stream.writeframes(struct.pack(f"<{len(pcm)}h", *pcm))
    data = destination.read_bytes()
    actual_peak = max(abs(value) for value in pcm) / 32768
    return {
        "id": f"audio.{name}",
        "file": destination.name,
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "sampleRate": RATE,
        "channels": 1,
        "bitDepth": 16,
        "durationMs": round(duration * 1000),
        "samplePeakDbfs": round(20 * math.log10(actual_peak), 2),
        "truePeakDbtp": None,
        "status": "audition_candidate",
        "listeningApproved": False,
        "preload": False,
    }


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    cues = []
    for name, generator, peak in (
        ("soft_tap", soft_tap, -25.0),
        ("paper_open", paper_open, -27.0),
        ("arrival", arrival, -23.0),
    ):
        values, description = generator()
        entry = write_cue(name, values, peak)
        entry["description"] = description
        cues.append(entry)
        print(f"{name}: {entry['durationMs']} ms, {entry['bytes']} bytes, {entry['samplePeakDbfs']} dBFS")
    manifest = {
        "schemaVersion": 1,
        "createdAt": "2026-09-13",
        "origin": "original_deterministic_synthesis",
        "sourceScript": "../../../../tool/audio/generate_cues.py",
        "sourceScriptSha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "seed": SEED,
        "thirdPartySamples": [],
        "rightsFile": "PROVENANCE.md",
        "playback": {
            "defaultEnabled": False,
            "requiresUserGestureOnWeb": True,
            "maxConcurrentVoices": 2,
            "triggerFromConfirmedStateOnly": ["audio.arrival"],
        },
        "assets": cues,
    }
    (OUTPUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
