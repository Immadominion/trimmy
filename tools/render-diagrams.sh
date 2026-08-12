#!/usr/bin/env bash
# mmd -> excalidraw scene -> hand-drawn SVG + PNG.
#
# The scene is the intermediate on purpose: mermaid's own SVG is the clean
# corporate style, and rendering the scene back out is what carries the
# whiteboard aesthetic into the docs.
set -uo pipefail
B="$HOME/.claude/skills/gstack/browse/dist/browse"
TAB=$(cat /tmp/trimmy-diagram-tab)
D=site/assets/diagrams
for f in "$@"; do
  SRC=$(base64 < "$D/$f.mmd" | tr -d '\n')
  S=$("$B" js --tab-id "$TAB" "window.__mermaidToExcalidraw(atob('$SRC')).then(j => { window.__scene = j; return 'scene ' + JSON.parse(j).elements.length })" 2>&1 | tail -1)
  if ! echo "$S" | grep -q scene; then printf "%-18s FAILED %s\n" "$f" "$(echo "$S" | head -c 120)"; continue; fi
  "$B" js --tab-id "$TAB" "window.__scene" --out "$D/$f.excalidraw" >/dev/null 2>&1
  SCENE=$(base64 < "$D/$f.excalidraw" | tr -d '\n')
  R=$("$B" js --tab-id "$TAB" "window.__excalidrawToSvg(atob('$SCENE')).then(s => { window.__hs = s; return 'svg ' + s.length })" 2>&1 | tail -1)
  if ! echo "$R" | grep -q svg; then printf "%-18s SVG FAILED\n" "$f"; continue; fi
  "$B" js --tab-id "$TAB" "window.__hs" --out "$D/$f.svg" >/dev/null 2>&1
  "$B" js --tab-id "$TAB" "window.__rasterize(window.__hs, 1600)" --out "$D/$f.png" >/dev/null 2>&1
  printf "%-18s %-12s %s\n" "$f" "$S" "$R"
done
