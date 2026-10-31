#!/bin/bash
# Builds a macOS .icns from a 1024×1024 PNG via an .iconset (sips + iconutil).
#   scripts/make-icns.sh build/AppIcon.png App/Resources/AppIcon.icns
set -euo pipefail
IN="${1:?usage: make-icns.sh in.png out.icns}"
OUT="${2:?usage: make-icns.sh in.png out.icns}"
[[ -f "$IN" ]] || { echo "no such file: $IN"; exit 1; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
SET="$WORK/AppIcon.iconset"; mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$IN" --out "$SET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$IN" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
mkdir -p "$(dirname "$OUT")"
iconutil -c icns "$SET" -o "$OUT"
echo "wrote $OUT"
