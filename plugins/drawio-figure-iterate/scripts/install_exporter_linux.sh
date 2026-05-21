#!/usr/bin/env bash
# Set up the headless draw.io Desktop exporter on Linux without admin/FUSE.
#
# The raw AppImage fails with `libfuse.so.2` in headless/container environments,
# so we extract it and call the inner binary with APPDIR set. This script
# downloads a draw.io Desktop AppImage, extracts it, and prints the resulting
# binary path and the env you need.
#
# Usage:
#   install_exporter_linux.sh [version]
#   (version defaults to a recent release tag; override if you need another)
#
# After it finishes, either:
#   export DRAWIO_BIN="$HOME/bin/drawio-desktop/squashfs-root/drawio"
# or rely on the default DRAWIO_APPDIR that export_png.sh already looks for.
set -euo pipefail

VERSION="${1:-24.7.17}"
DEST="$HOME/bin/drawio-desktop"
APPIMAGE="drawio-x86_64-${VERSION}.AppImage"
URL="https://github.com/jgraph/drawio-desktop/releases/download/v${VERSION}/${APPIMAGE}"

mkdir -p "${DEST}"
cd "${DEST}"

if [[ ! -f "${APPIMAGE}" ]]; then
  echo "Downloading ${URL}" >&2
  curl -fL -o "${APPIMAGE}" "${URL}"
fi
chmod +x "${APPIMAGE}"

echo "Extracting AppImage (no FUSE needed)..." >&2
"./${APPIMAGE}" --appimage-extract >/dev/null

BIN="${DEST}/squashfs-root/drawio"
if [[ ! -x "${BIN}" ]]; then
  echo "ERROR: expected binary not found at ${BIN}" >&2
  exit 1
fi

cat <<EOF

Done. Headless exporter ready:
  ${BIN}

export_png.sh finds it automatically (DRAWIO_APPDIR defaults to
  ${DEST}/squashfs-root).

To pin it explicitly, add to your shell profile:
  export DRAWIO_BIN="${BIN}"

Smoke test:
  scripts/export_png.sh some_figure.drawio /tmp/out.png 2
EOF
