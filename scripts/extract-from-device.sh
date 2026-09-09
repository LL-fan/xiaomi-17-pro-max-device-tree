#!/usr/bin/env bash
# Extract the stock device-tree blobs from a working Xiaomi 17 Pro Max over adb
# and decompile them, so the DTS sources in this repo can be regenerated/audited.
#
# Requirements: adb (root via su), dtc + fdtoverlay (device-tree-compiler),
# and AOSP host tool `unpack_bootimg` (set UNPACK_BOOTIMG to its path).
#
# Usage: ./scripts/extract-from-device.sh [out_dir]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/original/from-device}"
ADB="${ADB:-adb}"
: "${UNPACK_BOOTIMG:=unpack_bootimg}"
mkdir -p "$OUT"

echo "[*] current slot:"; SLOT="$($ADB shell su 0 getprop ro.boot.slot_suffix | tr -d '\r')"
echo "    slot=${SLOT:-_a}"
SUFFIX="${SLOT:-_a}"

echo "[*] dumping vendor_boot${SUFFIX} and dtbo${SUFFIX} (by-name symlinks)"
$ADB shell su 0 sh -c "dd if=/dev/block/by-name/vendor_boot${SUFFIX} of=/data/local/tmp/vb.img bs=1M"
$ADB shell su 0 sh -c "dd if=/dev/block/by-name/dtbo${SUFFIX}      of=/data/local/tmp/dtbo.img bs=1M"
$ADB pull /data/local/tmp/vb.img   "$OUT/vendor_boot.img"
$ADB pull /data/local/tmp/dtbo.img "$OUT/dtbo-partition.img"

echo "[*] unpacking vendor_boot -> base dtb"
mkdir -p "$OUT/vb"; "$UNPACK_BOOTIMG" --boot_img "$OUT/vendor_boot.img" --out "$OUT/vb"
cp "$OUT/vb/dtb" "$OUT/stock-base.dtb"

echo "[*] splitting dt_table and decompiling"
python3 "$ROOT/scripts/mkdtimage.py" dump "$OUT/dtbo-partition.img"
python3 - "$OUT/dtbo-partition.img" "$OUT" <<'PY'
import struct, sys, subprocess, os
img, out = sys.argv[1], sys.argv[2]
d=open(img,"rb").read()
_,total,_,esz,cnt,eoff,page,_=struct.unpack_from(">8I",d,0)
for i in range(cnt):
    sz,off,*_=struct.unpack_from(">8I",d,eoff+i*esz)
    open(os.path.join(out,f"board-overlay-{i}.dtbo"),"wb").write(d[off:off+sz])
PY
dtc -I dtb -O dts "$OUT/stock-base.dtb" > "$OUT/extracted-base.dts" 2>/dev/null
dtc -I dtb -O dts "$OUT/board-overlay-0.dtbo" > "$OUT/extracted-board-overlay.dts" 2>/dev/null

echo "[*] merging base + board overlay into the final live tree"
fdtoverlay -i "$OUT/stock-base.dtb" -o "$OUT/merged.dtb" "$OUT/board-overlay-0.dtbo"
dtc -I dtb -O dts "$OUT/merged.dtb" > "$OUT/xiaomi-17-pro-max.dts" 2>/dev/null
echo "[done] extracted + decompiled into $OUT"
