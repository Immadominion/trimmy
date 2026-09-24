# Welcome entrance sound sources

## Current mix v4

Runtime: `wall_street_orbit_v4.wav`, 2.15 seconds, 48 kHz stereo PCM16.
Measured sample peak: -10.2 dBFS; mean level: -28.8 dBFS before the
runtime's 34 percent default gain. SHA-256:
`57958a5c659ef53d83470ce91e2640125fd315f5f57c4f4ff5ecf77b877931ed`.
Reproduce from the repo root with `sh trimmy/tool/audio/mix_welcome_v4.sh`.

This is a restrained edit of one existing Mixkit creator-made sound effect,
**Magic transition sweep presentation** (catalog item 2638):
`mixkit-magic-transition-sweep-presentation-2638.wav`, source SHA-256
`6d77a7509e4d6b00600a663a28c3a6c8b231886bd3e50f789e6604bc1ff84593`.
Its original 3.94-second swell is trimmed to match the 2.15-second coin
entrance, gently filtered, faded and lowered. There are no inserted pops,
button clicks, separately triggered accents or generated sound sources. The
sound remains one continuous rise and decay. The prior `light-pop-whoosh`
source and both v2/v3 entrance mixes are excluded from the mobile bundle.
The two intro selection haptics were also removed, leaving one light tactile
landing at 1830 ms.

Catalog: https://mixkit.co/free-sound-effects/woosh/
Sound Effects Free License: https://mixkit.co/license/modal/sfxFree/

The Mixkit license allows use and modification in commercial video games and
does not require attribution. It does not allow redistributing a source sound
as standalone stock, a tool/template, or alongside public source files. Keep
the downloaded original in the internal art workspace; ship only the edited
cue embedded in the app. Mixkit describes its catalog as creator-made, but
we cannot independently verify the production method of every library file.
No generative model was used to make this v4 edit.

`mixkit-air-woosh-1489.wav` was also obtained as an audition candidate from
the same licensed catalog (SHA-256
`fdc4f87eb2c6d29ec3567b299fdc3b2aeea2432afe27801db80c496bda084499`);
it is not in the runtime mix.

The user heard this cue on iPhone after hot restart and liked it. First-launch
timing needs a fresh physical check after the splash-preparation fix. iOS ambient playback respects the
silent switch, the user's local sound/volume settings cap playback at 40
percent, and the intro plays only on entering the Welcome screen.

## Previous mix v3

Runtime: `wall_street_orbit_v3.wav`, 2.15 seconds, 48 kHz stereo PCM16.
Measured sample peak: -10.0 dBFS; mean level: -34.0 dBFS before runtime gain.
SHA-256: `2776c8fc8ef989ebe7cffcc4a4006a80ec453af102b6e47fb5c205d27b2f9780`.
Reproduce from the repo root with `sh trimmy/tool/audio/mix_welcome_v3.sh`.
Uses only the same three Mixkit source recordings below. No synthesized audio.

The filtered swirl enters at 80 ms and fades before the landing; a softer
sparkle starts at 1100 ms. Pop accents start at 490 and 1800 ms, with short
attacks preceding the 520 and 1830 ms haptic cues. A middle selection tick
at 1180 ms accompanies the sparkle. All material ends by 2.15 seconds.
High-pass/low-pass filtering reduces rumble and sharpness; a peak limiter and
short tail fade prevent clipping and an abrupt ending. This is a custom edit
of shared library recordings, not an exclusive proprietary sound recording.

The review volume preference defaults to and caps at 40 percent. Entrance
playback uses 85 percent of that value (34 percent by default); the existing
160 ms `welcome_press_v1.wav` uses the full setting. Settings persist sound,
haptics and volume locally. Primary CTA taps share a player across page
transitions, so leaving Welcome does not dispose its tap mid-playback.
Mute, background and navigation cancellation invalidate pending entrance
playback. iOS uses ambient audio and respects silent mode. Idle is silent.

Listening approval on iPhone speakers/headphones remains pending. Timing in
the file and haptic scheduling are verified separately from native latency.

## Previous mix v2

Runtime: `wall_street_orbit_v2.wav`, 2.15 seconds; `welcome_press_v1.wav`,
160 milliseconds. Both use the source clips listed below, not synthesis.
The entrance layers a filtered swirling sweep from 80 ms, a restrained sparkle
from 850 ms and light-pop accents at 520 and 1810 ms. Fades and limiting keep
the tail contained. Button feedback is a short, filtered excerpt of the pop.
Both are 48 kHz stereo PCM16. Measured sample peaks before runtime gain:
entrance -10.0 dBFS; button -6.9 dBFS. Runtime gains are 0.34 and 0.40.

iOS uses the ambient audio category to respect silent mode. Idle motion makes
no sound. Leaving the page or backgrounding cancels the entrance and pending
haptics; resume does not replay it. Device listening approval remains pending.

## Previous mix v1

23 September 2026. The runtime `wall_street_orbit_v1.wav` is an edited mix of
existing sound-library recordings, not synthesized audio.

Source catalog: https://mixkit.co/free-sound-effects/whoosh/
License reference: https://mixkit.co/license/#sfxFree

- Swirling whoosh: `mixkit-swirling-whoosh-1493.mp3`
- Magic sparkle whoosh: `mixkit-magic-sparkle-whoosh-2350.mp3`
- Light pop whoosh: `mixkit-light-pop-whoosh-3005.mp3`

Edits: trim, filtering, fades, gain, delayed pop, mixing and limiting.
Output: 2.15 seconds, 48 kHz, stereo PCM 16-bit. Runtime gain: 0.34.
SHA-256: `05202dcbaf79e7498951c2d8053ab7d396f9b820010cce247a7af9ead0f1f534`.

Android screen recordings have no sound track. They prove visual timing only;
physical sound audition and user approval remain pending.
