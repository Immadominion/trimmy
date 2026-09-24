# Trimmy audio provenance

Welcome now uses sourced `wall_street_orbit_v4.wav` and `welcome_press_v1.wav`.
See the [Welcome source record](WELCOME_SOURCES.md)
for library recordings, edit details, license and playback levels. The v4
entrance has no pop layer or selection ticks. The historical synthesized
candidates below are not used on Welcome.

## Original Trimmy sound candidates

Created 13 September 2026 by the project's deterministic Python synthesis script at `trimmy/tool/audio/generate_cues.py`. These recordings contain original mathematical oscillators and seeded noise, with **no third-party samples, music or voice recordings**. No external sound-library attribution is required for these particular files. Distribution rights follow the Trimmy project's chosen license; this file does not introduce a license for the rest of the repository or assert exclusive copyright in generated material.

| File | Intended use | Duration | Sample-peak target |
| --- | --- | --- | --- |
| `soft_tap.wav` | Optional quiet control feedback | 85 ms | −25 dBFS |
| `paper_open.wav` | User opens an offer letter | 290 ms | −27 dBFS |
| `arrival.wav` | Application reports a confirmed arrival | 530 ms | −23 dBFS |

All are mono 48 kHz PCM16 WAVs. The script removes DC bias, fades boundaries and attenuates each cue. Sample peaks are not true-peak measurements or loudness guarantees. Exact sizes, checksums and script provenance are in `manifest.json`. A separate ffmpeg check decoded every file successfully and measured true peaks of −25, −27 and −23 dBTP respectively; see `VERIFICATION.json`. All three WAVs reproduced byte-for-byte from the script.

The cues are **audition candidates**, not a claim of listening-approved final audio. Audition on a phone speaker, laptop and earbuds before changing that status. Playback must be off until the user enables sound, with a persistent mute control and volume preference. On web, initialize/unlock playback from a user gesture and handle blocked playback gracefully. Never derive transaction success from a sound; trigger `arrival` from confirmed application state, and always provide visible status.

Regenerate from the repository root:

```sh
python3 tool/audio/generate_cues.py
```
