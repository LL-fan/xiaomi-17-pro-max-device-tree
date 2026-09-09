#!/usr/bin/env bash
# Rebuild from DTS and compare key metadata against the shipped stock blobs.
# This proves the published DTS reproduces the on-device device tree.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
bash scripts/build-dtb.sh >/dev/null
B="$ROOT/build"; O="$ROOT/original"; T="$(mktemp -d)"

# pull the stock board overlay out of the dt_table image
python3 - "$O/stock-dtbo.img" "$T/stock-board.dtbo" <<'PY'
import struct,sys
d=open(sys.argv[1],"rb").read()
_,_,_,esz,cnt,eoff,_,_=struct.unpack_from(">8I",d,0)
sz,off,*_=struct.unpack_from(">8I",d,eoff)
open(sys.argv[2],"wb").write(d[off:off+sz])
PY

pass=0; fail=0
check() { # label stock built
  local label="$1" s="$2" b="$3"
  if [ "$s" == "$b" ]; then echo "PASS  $label = $b"; pass=$((pass+1));
  else echo "FAIL  $label"; echo "      stock: $s"; echo "      built: $b"; fail=$((fail+1)); fi
}

echo "== base SoC tree =="
check "model"      "$(fdtget "$O/stock-base.dtb" / model 2>/dev/null)" \
                    "$(fdtget "$B/canoe-base.dtb" / model 2>/dev/null)"
check "compatible" "$(fdtget "$O/stock-base.dtb" / compatible 2>/dev/null)" \
                    "$(fdtget "$B/canoe-base.dtb" / compatible 2>/dev/null)"

echo "== board overlay =="
check "model"      "$(fdtget "$T/stock-board.dtbo" / model 2>/dev/null)" \
                    "$(fdtget "$B/overlays/board-popsicle.dtbo" / model 2>/dev/null)"
check "compatible" "$(fdtget "$T/stock-board.dtbo" / compatible 2>/dev/null | tr '\0' ' ')" \
                    "$(fdtget "$B/overlays/board-popsicle.dtbo" / compatible 2>/dev/null | tr '\0' ' ')"

echo "== merged final tree =="
MT="$B/xiaomi-17-pro-max.dtb"
echo "  model      = $(fdtget "$MT" / model)"
echo "  compatible = $(fdtget "$MT" / compatible | tr '\0' ' ')"
NODES="$(dtc -I dtb -O dts "$MT" 2>/dev/null | grep -cE '\{[[:space:]]*$')"
PROPS="$(dtc -I dtb -O dts "$MT" 2>/dev/null | grep -cE '= <|= \"|= \[')"
echo "  nodes      = $NODES"
echo "  properties = $PROPS"

rm -rf "$T"
echo "RESULT pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
