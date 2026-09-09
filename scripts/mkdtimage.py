#!/usr/bin/env python3
# Minimal, dependency-free Android dt_table (dtbo.img/dt.img) packer.
# Layout follows AOSP system/libufdt dt_table_header / dt_table_entry (version 0).
#
# Usage:
#   mkdtimage.py create OUT.img [--page_size 4096] DTB1 [DTB2 ...]
#   mkdtimage.py dump IMG
import struct, sys, os

DT_TABLE_MAGIC = 0xD7B7AB1E
FDT_MAGIC = 0xD00DFEED
HEADER_SIZE = 32
ENTRY_SIZE = 32


def align_up(v, a):
    return (v + a - 1) // a * a


def create(out_path, dtbs, page_size=4096):
    blobs = []
    for p in dtbs:
        b = open(p, "rb").read()
        (magic,) = struct.unpack_from(">I", b, 0)
        if magic != FDT_MAGIC:
            raise SystemExit(f"{p}: not a flat device-tree blob (magic 0x{magic:08x})")
        blobs.append(b)

    n = len(blobs)
    # entries table sits right after the 32-byte header; data starts at page 1.
    table_bytes = HEADER_SIZE + n * ENTRY_SIZE
    cursor = align_up(table_bytes, page_size)
    entries = []
    regions = []
    for b in blobs:
        off = cursor
        entries.append((len(b), off))
        regions.append((off, b))
        cursor = align_up(off + len(b), page_size)
    total = cursor

    img = bytearray(total)
    struct.pack_into(">8I", img, 0,
                     DT_TABLE_MAGIC, total, HEADER_SIZE, ENTRY_SIZE,
                     n, HEADER_SIZE, page_size, 0)
    for i, (size, off) in enumerate(entries):
        struct.pack_into(">8I", img, HEADER_SIZE + i * ENTRY_SIZE,
                         size, off, 0, 0, 0, 0, 0, 0)
    for off, b in regions:
        img[off:off + len(b)] = b
    open(out_path, "wb").write(img)
    print(f"[mkdtimage] {out_path}: {n} dtb(s), total={total}, page={page_size}")


def dump(img_path):
    d = open(img_path, "rb").read()
    magic, total, hsz, esz, cnt, eoff, page, ver = struct.unpack_from(">8I", d, 0)
    if magic != DT_TABLE_MAGIC:
        raise SystemExit(f"not a dt_table (magic 0x{magic:08x})")
    print(f"magic=0x{magic:08x} total={total} entries={cnt} page={page} ver={ver}")
    for i in range(cnt):
        size, off, eid, rev, *_ = struct.unpack_from(">8I", d, eoff + i * esz)
        print(f"  [{i}] offset={off} size={size} id=0x{eid:x} rev={rev}")


def main(argv):
    if len(argv) >= 2 and argv[0] == "create":
        page = 4096
        rest = argv[1:]
        if "--page_size" in rest:
            k = rest.index("--page_size")
            page = int(rest[k + 1]); del rest[k:k + 2]
        out = rest[0]; dtbs = rest[1:]
        create(out, dtbs, page)
    elif len(argv) >= 2 and argv[0] == "dump":
        dump(argv[1])
    else:
        print(__doc__); sys.exit(1)


if __name__ == "__main__":
    main(sys.argv[1:])
