#!/usr/bin/env bash
# Headless PNG export for a .drawio file, cross-platform.
#
# Usage:
#   export_png.sh <input.drawio> [output.png] [scale]
#
# scale defaults to 2 (print quality); bump to 3 for dense diagrams.
#
# Resolution order for the draw.io binary:
#   1. $DRAWIO_BIN if set (absolute path to the draw.io executable)
#   2. Linux extracted AppImage at $DRAWIO_APPDIR/squashfs-root/drawio
#      (DRAWIO_APPDIR defaults to ~/bin/drawio-desktop/squashfs-root)
#   3. macOS app bundle
#   4. `drawio` / `draw.io` on PATH
#
# Linux note: the AppImage must be EXTRACTED (the raw AppImage fails with
# libfuse.so.2). See scripts/install_exporter_linux.sh. APPDIR must point at
# the squashfs-root so the internal launcher resolves its resources.
set -euo pipefail

IN="${1:?usage: export_png.sh <input.drawio> [output.png] [scale]}"
OUT="${2:-${IN%.drawio}.png}"
SCALE="${3:-2}"

run() { echo "+ $*" >&2; "$@"; }

# 1. Explicit override.
if [[ -n "${DRAWIO_BIN:-}" && -x "${DRAWIO_BIN}" ]]; then
  run "${DRAWIO_BIN}" --no-sandbox --export --format png --scale "${SCALE}" \
    --output "${OUT}" "${IN}"
  echo "Wrote ${OUT}" >&2; exit 0
fi

UNAME="$(uname -s)"

# 2. Linux extracted AppImage.
if [[ "${UNAME}" == "Linux" ]]; then
  APPDIR="${DRAWIO_APPDIR:-$HOME/bin/drawio-desktop/squashfs-root}"
  BIN="${APPDIR}/drawio"
  if [[ -x "${BIN}" ]]; then
    APPDIR="${APPDIR}" run "${BIN}" --no-sandbox --export --format png \
      --scale "${SCALE}" --output "${OUT}" "${IN}"
    echo "Wrote ${OUT}" >&2; exit 0
  fi
fi

# 3. macOS app bundle.
if [[ "${UNAME}" == "Darwin" ]]; then
  BIN="/Applications/draw.io.app/Contents/MacOS/draw.io"
  if [[ -x "${BIN}" ]]; then
    run "${BIN}" --export --format png --scale "${SCALE}" \
      --output "${OUT}" "${IN}"
    echo "Wrote ${OUT}" >&2; exit 0
  fi
fi

# 4. On PATH (covers Windows Git Bash 'draw.io.exe', native installs).
for CAND in drawio draw.io draw.io.exe; do
  if command -v "${CAND}" >/dev/null 2>&1; then
    run "${CAND}" --export --format png --scale "${SCALE}" \
      --output "${OUT}" "${IN}"
    echo "Wrote ${OUT}" >&2; exit 0
  fi
done

cat >&2 <<'EOF'
ERROR: no draw.io executable found.
  - Set DRAWIO_BIN to the absolute path of the draw.io binary, or
  - On Linux, run scripts/install_exporter_linux.sh to extract the AppImage, or
  - Install draw.io Desktop and ensure it is on PATH.
Fallback: open the .drawio in the browser editor (via the drawio MCP) and
export PNG manually with File -> Export as -> PNG; the scoring step still works.
EOF
exit 1
