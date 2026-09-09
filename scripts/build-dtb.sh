#!/usr/bin/env bash
# Reproducible build of the Xiaomi 17 Pro Max (popsicle / canoe / SM8850)
# device-tree binaries from the DTS sources in this repository.
#
# Outputs (under build/):
#   xiaomi-17-pro-max.dtb        merged final tree (base + board overlay)
#   canoe-base.dtb               SoC base tree (as shipped in vendor_boot)
#   overlays/*.dtbo              board / VM overlays
#   dtbo.img                     Android dt_table image (board overlay)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DTS="$ROOT/dts"
OUT="$ROOT/build"
OVOUT="$OUT/overlays"
LOG="$OUT/warnings.log"
: "${DTC:=dtc}"
: "${PAGE_SIZE:=4096}"

if ! command -v "$DTC" >/dev/null 2>&1; then
  echo "ERROR: dtc not found. Install device-tree-compiler (Debian/Ubuntu:"
  echo "       sudo apt-get install device-tree-compiler) or set DTC=/path/to/dtc" >&2
  exit 1
fi
echo "[build] dtc: $($DTC --version)"
mkdir -p "$OVOUT"
: > "$LOG"

compile() { # in.dts out.dtb [extra dtc args...]
  local in="$1" out="$2"; shift 2
  echo "[build] $(basename "$in") -> $(basename "$out")"
  "$DTC" -I dts -O dtb -@ "$@" -o "$out" "$in" 2>>"$LOG" || {
    echo "  dtc FAILED, see $LOG"; tail -n 20 "$LOG"; exit 1; }
}

# 1) SoC base tree (lives inside vendor_boot as `dtb`)
compile "$DTS/xiaomi-17-pro-max-common.dtsi" "$OUT/canoe-base.dtb"
# 2) Board overlay (lives on the dtbo partition)
compile "$DTS/overlays/board-popsicle-overlay.dts" "$OVOUT/board-popsicle.dtbo"
# 3) Trusted-VM overlays (qtvm_dtbo partition), optional
compile "$DTS/overlays/qtvm-svm-overlay.dts"   "$OVOUT/qtvm-svm.dtbo"
compile "$DTS/overlays/qtvm-oemvm-overlay.dts" "$OVOUT/qtvm-oemvm.dtbo"
# 4) Fully merged final tree (base + board overlay), easiest to read/flash standalone
compile "$DTS/xiaomi-17-pro-max.dts" "$OUT/xiaomi-17-pro-max.dtb"

# 5) Pack the board overlay into an Android dt_table image (dtbo partition layout)
python3 "$ROOT/scripts/mkdtimage.py" create "$OUT/dtbo.img" \
  --page_size "$PAGE_SIZE" "$OVOUT/board-popsicle.dtbo"

echo "[build] done. artifacts in $OUT (warnings: $LOG)"
ls -la "$OUT" "$OVOUT"
