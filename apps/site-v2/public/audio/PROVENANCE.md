# Current landing-page audio — 23 September 2026

## reading-piano.mp3

**Gymnopedie No. 1 — Kevin MacLeod (incompetech.com).** Composition by Erik Satie.
Licensed under Creative Commons: By Attribution 4.0:
https://creativecommons.org/licenses/by/4.0/

- Official recording: https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100787
- Official catalog: https://incompetech.com/music/royalty-free/pieces.json
- Original MP3: https://incompetech.com/music/royalty-free/mp3-royaltyfree/Gymnopedie%20No%201.mp3
- ISRC: USUAN1100787. Catalog: piano, 77 BPM, released 10 January 2011.
- Credit requirements: https://incompetech.com/music/royalty-free/faq.html

This is the existing Kevin MacLeod recording, not a new AI generation. The
recording is licensed, not claimed to be public domain. A hover/focus credit
on the existing sound control links to `/audio/CREDITS.html`.

Changes: constant gain reduction of 9.01 dB and MP3 re-encoding at 160 kbit/s,
stereo 44.1 kHz. The full 187.089-second performance remains in order, including
its natural ending and brief final silence. No beat, added instrument, time
stretch, compressor or circular musical splice was introduced.

| Measurement | Original recording | Quiet website master |
|---|---:|---:|
| Integrated loudness | -19.99 LUFS | -29.44 LUFS |
| True peak | -0.10 dBTP | -9.58 dBTP |
| Loudness range | 9.00 LU | 8.90 LU |

The runtime music gain remains exactly 0.30 (another 10.46 dB attenuation).
Music stays paused and silent throughout the opening, history and floor chapter.
It starts only on arrival at index 8 and after the room sound has finished
fading. It continues through later chapters, fades when returning before index
8, and is guaranteed silent by position 7.65 before floor ambience can return.
Mute and hidden-tab pause apply to both tracks.

## floor-quiet.mp3

The existing floor mix, reduced by a constant 10 dB and encoded as mono,
44.1 kHz, 160 kbit/s MP3. Runtime gain remains exactly 0.50. It is a composed
crowd ambience, not a recording of an actual stock exchange.

Original sources from https://mixkit.co/free-sound-effects/crowd/:

- Big crowd talking loop, SFX 364: bed, band limited 120 Hz to 6 kHz.
- Angry male crowd ambience, SFX 458: at 35 percent, entering after 1.5 seconds,
  band limited 200 Hz to 5 kHz.

These use the Mixkit Free Sound Effects License:
https://mixkit.co/license/#sfxFree. Commercial use is permitted; attribution is
not required. The earlier mix's 1.2-second entrance fade and 3-second ending
fade are preserved.

| Measurement | Previous floor mix | Quiet website master |
|---|---:|---:|
| Integrated loudness | -18.33 LUFS | -28.78 LUFS |
| True peak | -0.77 dBTP | -11.21 dBTP |
| Loudness range | 7.40 LU | 7.50 LU |

## Source and verification

The original piano download, archived previous floor mix, official catalog
metadata, licensing snapshots, mastering script and measurements are in
`trimmy/art/production/reading-audio-2026-09-23/`.

The earlier generated `music.mp3` is retired from playback. SoundSwitch maps
the existing App music prop to `reading-piano.mp3`; Ambience maps the old floor
path to `floor-quiet.mp3`, avoiding cached versions of the louder files.

Checks cover full-file decoding, true peaks, integrated loudness, dynamic range
and preserved duration. A sound-state test verified narrative ordering, no
channel overlap, exact volume ceilings, mute, visibility pause/resume and
guarded autoplay retries. No subjective listening pass is claimed: this agent
had no audio-listening tool.
