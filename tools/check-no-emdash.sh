#!/usr/bin/env bash
# Fails if an em dash (U+2014) reaches anything a person reads.
#
# This is a house style rule, not a typographic one. The em dash is the single
# most recognisable tell of machine-written prose, and this project's whole
# claim is that a human measured these numbers. A colon, a full stop or a pair
# of brackets says the same thing without the tell.
#
# Scope is deliberately the public surface plus the code that produces it.
# The research/ notes are working papers and are left alone.
#
# Usage: tools/check-no-emdash.sh        (exit 1 on any hit)
set -uo pipefail
cd "$(dirname "$0")/.."

TARGETS=(
  site/index.html site/llms.txt site/robots.txt site/build.sh
  site/assets/page.css site/assets/trimmy.css
  web/index.html web/arm.js web/lib
  README.md docs/ROADMAP.md
)

hits=0
for t in "${TARGETS[@]}"; do
  [ -e "$t" ] || continue
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    echo "  $line"
    hits=$((hits + 1))
  done < <(grep -rn $'—' "$t" 2>/dev/null)
done

# Generated artefacts inherit from their sources, so check them separately and
# point at the source rather than at the generated file.
for g in site/index.md site/llms-full.txt site/arm/index.html site/arm/arm.js; do
  [ -e "$g" ] || continue
  n=$(grep -c $'—' "$g" 2>/dev/null || true)
  if [ "${n:-0}" -gt 0 ]; then
    echo "  $g has $n (generated - fix the source, then re-run site/build.sh)"
    hits=$((hits + n))
  fi
done

if [ "$hits" -gt 0 ]; then
  echo
  echo "FAIL: $hits em dash(es) in user-facing text."
  echo "Use a colon, a full stop, or brackets instead."
  exit 1
fi
echo "ok: no em dashes in user-facing text"
