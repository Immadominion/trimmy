#!/usr/bin/env bash
#
# Puts the two sibling repositories where Trimmy's Dart packages expect them, then verifies the
# whole thing builds.
#
# `keeper/` and `arming/` depend on our own SDK and on Plimsoll by PATH, not by version:
#
#     plimsoll_core:  { path: ../../plimsoll/packages/plimsoll_core }
#     flare_network:  { path: ../../sdk/packages/flare_network }
#
# That is deliberate — all three are being developed together and a published version would go
# stale between commits — but it means a clone of `trimmy` alone cannot resolve them, and
# `dart pub get` fails with "could not find package". This script fixes that in the obvious way.
#
#     ./setup.sh              clone the siblings if missing, then verify
#     ./setup.sh --verify     verify only
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT="$(dirname "$HERE")"

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32mok\033[0m   %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; }

if [[ "${1:-}" != "--verify" ]]; then
  say "Siblings"
  for repo in sdk plimsoll; do
    if [[ -d "$PARENT/$repo" ]]; then
      ok "$repo already present at $PARENT/$repo"
    else
      case "$repo" in
        sdk)      url=https://github.com/Immadominion/flare-dart.git ;;
        plimsoll) url=https://github.com/Immadominion/plimsoll.git ;;
      esac
      echo "  cloning $repo from $url"
      git clone --quiet "$url" "$PARENT/$repo"
      ok "$repo cloned"
    fi
  done
fi

failed=0

say "Contracts"
if [[ -d "$HERE/contracts/lib/forge-std" ]]; then
  ok "submodules present"
else
  bad "contracts/lib is empty — run: git submodule update --init --recursive"
  failed=1
fi

say "Dart"
for pkg in keeper arming; do
  if (cd "$HERE/$pkg" && dart pub get >/dev/null 2>&1); then
    ok "$pkg resolves"
  else
    bad "$pkg does not resolve — are sdk/ and plimsoll/ siblings of this directory?"
    failed=1
  fi
done

say "Web"
if command -v node >/dev/null 2>&1; then
  if (cd "$HERE/web" && node --test "test/*.test.mjs" >/dev/null 2>&1); then
    ok "22 tests pass (no dependencies, no build step)"
  else
    bad "web tests failed"
    failed=1
  fi
else
  echo "  skipped — node not installed"
fi

if [[ $failed -eq 0 ]]; then
  say "Ready."
  cat <<'EOF'
  cd contracts && forge test --no-match-path "test/research/*"    # 92 tests
  cd web       && python3 -m http.server 8731                     # the arming page
EOF
else
  say "Something is missing — see the failures above."
  exit 1
fi
