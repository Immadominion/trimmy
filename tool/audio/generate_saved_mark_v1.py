#!/usr/bin/env python3
"""Reproduce the original, nonmusical saved-answer stamp audition candidate.

No external recordings or libraries. This does not replace the earlier cues.
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
DURATION = 0.140
SEED = 0x53415645
ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "apps/mobile/assets/audio/saved_mark_v1.wav"


def edge(t: float) -> float:
    attack = 0.5 - 0.5 * math.cos(math.pi * min(1.0, t / 0.004))
    release = 0.5 - 0.5 * math.cos(
        math.pi * min(1.0, max(0.0, (DURATION - t) / 0.025))
    )
    return attack * release


def main() -> None:
    rng = random.Random(SEED)
    low = 0.0
    lower = 0.0
    values = []
    for i in range(round(RATE * DURATION)):
        t = i / RATE
        low += 0.16 * (rng.uniform(-1, 1) - low)
        lower += 0.02 * (low - lower)
        # One low, quickly damped stamp with a short paper-fibre transient.
        # There is no pitch sequence, reward melody or cash-register sample.
        phase = 2 * math.pi * (260 * t - 120 * t * t)
        wood = math.sin(phase) * math.exp(-t * 62)
        fibre = (low - lower) * math.exp(-((t - 0.018) / 0.013) ** 2)
        values.append((0.8 * wood + 0.45 * fibre) * edge(t))
    mean = sum(values) / len(values)
    values = [(v - mean) * edge(i / RATE) for i, v in enumerate(values)]
    scale = 10 ** (-24 / 20) / max(abs(v) for v in values)
    pcm = [round(v * scale * 32767) for v in values]
    pcm[0] = pcm[-1] = 0
    OUTPUT.parent.mkdir(exist_ok=True, parents=True)
    with wave.open(str(OUTPUT), "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(RATE)
        stream.writeframes(struct.pack(f"<{len(pcm)}h", *pcm))
    manifest = {
        "schemaVersion": 1,
        "id": "audio.saved_mark_v1",
        "file": OUTPUT.name,
        "origin": "original_deterministic_synthesis",
        "sourceScript": "../../../../tool/audio/generate_saved_mark_v1.py",
        "sourceScriptSha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "sha256": hashlib.sha256(OUTPUT.read_bytes()).hexdigest(),
        "seed": SEED,
        "thirdPartySamples": [],
        "rights": "Original oscillators and seeded noise; no external sample attribution. Distribution follows the project's chosen license; no exclusive copyright claim is made.",
        "description": "One muted wooden stamp and short paper-fibre transient for a successfully saved practice answer.",
        "bytes": OUTPUT.stat().st_size,
        "sampleRate": RATE,
        "channels": 1,
        "bitDepth": 16,
        "durationMs": round(DURATION * 1000),
        "samplePeakDbfs": round(20 * math.log10(max(abs(v) for v in pcm) / 32768), 2),
        "firstSample": pcm[0],
        "lastSample": pcm[-1],
        "status": "audition_candidate",
        "listeningApproved": False,
        "playback": {"defaultEnabled": False, "loop": False, "trigger": "successful_progress_write_only"},
    }
    OUTPUT.with_suffix(".provenance.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"{OUTPUT.name}: {len(pcm)} samples, 140 ms, {manifest['samplePeakDbfs']} dBFS, {manifest['sha256']}")


if __name__ == "__main__":
    main()
