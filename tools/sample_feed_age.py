#!/usr/bin/env python3
"""Settle O-2: the production `maxFeedAge`.

Measures `block.timestamp - feedTimestamp` — the quantity a CONTRACT sees — by pinning an
`eth_call` of `getFeedById` to each block and pairing it with that block's own timestamp. Earlier
passes measured `wallclock_at_curl - ts`, which is a different number with the RPC cache in between.

One calm window is not enough: a separate window on 2026-08-06 saw feed ages to 31 s while another
saw a max of 7 s. Production is episodically bursty, so this samples several SEPARATED windows and
reports the max of the per-window p99s.
"""
import json, statistics, sys, time, urllib.request

RPC = "https://coston2-api.flare.network/ext/C/rpc"
FTSO = "0xC4e9c78EA53db782E28f28Fdf80BaF59336B304d"
FEED_XRP = "015852502f55534400000000000000000000000000"
SELECTOR = "0x93e9f806"  # getFeedById(bytes21) -- verified with `cast sig`, not recalled

def rpc(batch):
    req = urllib.request.Request(RPC, data=json.dumps(batch).encode(),
                                 headers={"content-type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=30))

def latest_block():
    return int(rpc([{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}])[0]["result"], 16)

def sample_window(n_blocks):
    tip = latest_block()
    lo = tip - n_blocks + 1
    blocks = rpc([{"jsonrpc":"2.0","id":i,"method":"eth_getBlockByNumber",
                   "params":[hex(b), False]} for i, b in enumerate(range(lo, tip + 1))])
    calls = rpc([{"jsonrpc":"2.0","id":i,"method":"eth_call",
                  "params":[{"to": FTSO, "data": SELECTOR + FEED_XRP + "0"*22}, hex(b)]}
                 for i, b in enumerate(range(lo, tip + 1))])
    by_id_b = {r["id"]: r for r in blocks}
    by_id_c = {r["id"]: r for r in calls}

    ages, gaps, prev_ts, errors = [], [], None, []
    for i in range(n_blocks):
        rb, rc = by_id_b.get(i), by_id_c.get(i)
        if not rb or not rc or "result" not in rc or rc.get("result") in (None, "0x"):
            # Report rather than skip. An earlier version swallowed every failure here and
            # produced six empty windows in silence, which looked identical to "no data yet".
            errors.append((rc or {}).get("error") or "empty result")
            continue
        bts = int(rb["result"]["timestamp"], 16)
        raw = rc["result"][2:]
        feed_ts = int(raw[128:192], 16)          # third word: uint64 timestamp
        ages.append(bts - feed_ts)
        if prev_ts is not None:
            gaps.append(bts - prev_ts)
        prev_ts = bts
    if errors:
        print(f"  !! {len(errors)} failed call(s), first: {errors[0]}", flush=True)
    return ages, gaps

def pct(xs, p):
    if not xs: return None
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(len(xs) * p / 100))]

def main():
    windows = int(sys.argv[1]) if len(sys.argv) > 1 else 6
    blocks = int(sys.argv[2]) if len(sys.argv) > 2 else 150
    spacing = int(sys.argv[3]) if len(sys.argv) > 3 else 240

    p99s, maxes, all_ages = [], [], []
    for w in range(windows):
        ages, gaps = sample_window(blocks)
        if not ages:
            print(f"window {w+1}: no samples", flush=True); continue
        all_ages += ages
        p99s.append(pct(ages, 99)); maxes.append(max(ages))
        print(f"window {w+1}/{windows}  n={len(ages):3d}  age p50={pct(ages,50)}s "
              f"p90={pct(ages,90)}s p99={pct(ages,99)}s max={max(ages)}s  "
              f"| gap p50={pct(gaps,50)}s max={max(gaps) if gaps else '-'}s", flush=True)
        if w < windows - 1:
            time.sleep(spacing)

    if all_ages:
        print("\n=== O-2 result ===")
        print(f"windows={len(p99s)}  total samples={len(all_ages)}")
        print(f"per-window p99s : {p99s}")
        print(f"per-window maxes: {maxes}")
        print(f"MAX of p99s     : {max(p99s)}s   <- the parameter, per GROUND-TRUTH")
        print(f"global max      : {max(all_ages)}s")
        print(f"recommended maxFeedAge (2x max-of-p99, floored at 60): "
              f"{max(60, max(p99s) * 2)}s")

main()
