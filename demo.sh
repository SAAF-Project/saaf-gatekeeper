#!/usr/bin/env bash
# Runs gatekeeper over every git repo in a folder of SAAF clones and prints one line per repo.
set -uo pipefail

gk="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gatekeeper.sh"
root="${1:-$HOME/workspace/saaf}"
[ $# -gt 0 ] && shift
clean=0; flagged=0

if [ $# -gt 0 ]; then
  dirs=(); for name in "$@"; do dirs+=("$root/$name"); done
else
  dirs=("$root"/*/)
fi

for dir in "${dirs[@]}"; do
  dir="${dir%/}"
  name="$(basename "$dir")"
  [ "$name" = saaf-gatekeeper ] && continue
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || continue
  out="$("$gk" "$dir" 2>&1)"
  case $? in
    0) clean=$((clean + 1)) ;;
    1) flagged=$((flagged + 1)); printf '%s\n' "$out" | grep '^FAIL' | sed -E "s/  fingerprint .*//; s|^|$name  |" ;;
    *) printf '%s  ERROR %s\n' "$name" "$out" ;;
  esac
done
echo
echo "$flagged repos flagged, $clean clean"
