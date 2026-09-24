#!/bin/sh
# Run from the repository root. Only edits the licensed recordings listed in
# source-audio/PROVENANCE.md. No synthesized tones or generated sound sources.
set -eu
source_dir=trimmy/art/studies/welcome-orbit-2026-09-23/source-audio
destination=trimmy/apps/mobile/assets/audio/wall_street_orbit_v3.wav
ffmpeg -hide_banner -loglevel warning -y \
  -i "$source_dir/mixkit-swirling-whoosh-1493.mp3" \
  -i "$source_dir/mixkit-magic-sparkle-whoosh-2350.mp3" \
  -i "$source_dir/mixkit-light-pop-whoosh-3005.mp3" \
  -filter_complex '
    [0:a]atrim=0:1.7,asetpts=PTS-STARTPTS,highpass=f=180,lowpass=f=4800,afade=t=in:d=0.12,afade=t=out:st=0.85:d=0.85,volume=0.30,adelay=80|80[sweep];
    [1:a]atrim=0:0.9,asetpts=PTS-STARTPTS,highpass=f=800,lowpass=f=5800,afade=t=in:d=0.055,afade=t=out:st=0.25:d=0.65,volume=0.11,adelay=1100|1100[glint];
    [2:a]atrim=0:0.16,asetpts=PTS-STARTPTS,highpass=f=200,lowpass=f=3600,afade=t=in:d=0.004,afade=t=out:st=0.05:d=0.11,asplit=2[pop1][pop2];
    [pop1]volume=0.17,adelay=490|490[first];
    [pop2]volume=0.26,adelay=1800|1800[settle];
    [sweep][glint][first][settle]amix=inputs=4:normalize=0,volume=1.7,alimiter=limit=0.32:level=false:latency=true,apad=whole_dur=2.15,atrim=0:2.15,afade=t=out:st=1.98:d=0.17[out]
  ' -map '[out]' -ar 48000 -ac 2 -c:a pcm_s16le "$destination"
