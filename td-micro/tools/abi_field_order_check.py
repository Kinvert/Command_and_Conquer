#!/usr/bin/env python3
"""Compare Zig and C struct field ORDER, not just size.

economy_wins was last in batch.Stats and third from the end in TdMicroBatchStatsV2. Both structs
were 424 bytes, so the size assertion passed and the C side silently read a different counter --
the reported economy_win_rate was an episode share, and a sweep optimised it for hours.

usage: python3 tools/abi_field_order_check.py   (exit 1 on any mismatch)
"""
import re, sys, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
zig = (root / "src" / "batch.zig").read_text()
hdr = (root / "include" / "td_micro_api.h").read_text()

def zig_fields(name):
    m = re.search(rf"pub const {name} = extern struct \{{(.*?)\n\}};", zig, re.S)
    return re.findall(r"^\s+([a-z_0-9]+):\s*(?:u64|f64|f32|u32)", m.group(1), re.M)

def c_fields(name):
    m = re.search(rf"typedef struct {name} \{{(.*?)\}} {name};", hdr, re.S)
    return re.findall(r"^\s+(?:uint64_t|uint32_t|double|float)\s+([a-z_0-9]+);", m.group(1), re.M)

PAIRS = [("Stats", "TdMicroBatchStatsV2"),
         ("Metrics", "TdMicroBatchMetrics"),
         ("RewardConfig", "TdMicroRewardConfig")]

failed = False
for zname, cname in PAIRS:
    z, c = zig_fields(zname), c_fields(cname)
    if z == c:
        print(f"OK   {zname} == {cname}  ({len(z)} fields, same order)")
        continue
    failed = True
    print(f"FAIL {zname} != {cname}  (zig={len(z)} c={len(c)})")
    for i in range(min(len(z), len(c))):
        if z[i] != c[i]:
            print(f"       first mismatch at index {i}: zig={z[i]} c={c[i]}")
            break
    for f in [f for f in z if f not in c]:
        print(f"       zig-only: {f}")
    for f in [f for f in c if f not in z]:
        print(f"       c-only:   {f}")

sys.exit(1 if failed else 0)
