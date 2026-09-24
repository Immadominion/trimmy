#!/bin/sh
# Run from the repository root. The single source is the creator-made,
# Mixkit-licensed recording documented in source-audio/PROVENANCE.md.
set -eu
source_dir=trimmy/art/studies/welcome-orbit-2026-09-23/source-audio
destination=trimmy/apps/mobile/assets/audio/wall_street_orbit_v4.wav
ffmpeg -hide_banner -loglevel warning -y \
  -i "$source_dir/mixkit-magic-transition-sweep-presentation-2638.wav" \
  -af 'atrim=0:2.15,asetpts=PTS-STARTPTS,highpass=f=120,lowpass=f=6500,afade=t=in:d=0.12,afade=t=out:st=1.88:d=0.27,volume=0.50,alimiter=limit=0.35:level=false:latency=true' \
  -ar 48000 -ac 2 -c:a pcm_s16le "$destination"
