#!/usr/bin/env python3
"""Two measurements the oracle lens needs, both read exactly as the contract sees them:
eth_call PINNED to a block, paired with that same block's own timestamp.

(1) signed feed age (block.timestamp - feed.timestamp) for both allowlisted feeds, so the
    "feed publishes ahead of the block clock" branch of Quote.requireFresh can be counted
    rather than argued about.
(2) drift of the XRP/FLR relative price over LATCH-sized horizons (minutes to a day), which
    is the quantity Trimmy.latchedPrice is frozen against for the whole life of a rule.

usage: sample_latch_drift.py [span_blocks] [stride]
"""
import json, sys, urllib.request

RPC = "https://coston2-api.flare.network/ext/C/rpc"
FTSO = "0xC4e9c78EA53db782E28f28Fdf80BaF59336B304d"
XRP = "015852502f55534400000000000000000000000000"
FLR = "01464c522f55534400000000000000000000000000"
SEL = "0x93e9f806"  # getFeedById(bytes21)


def rpc(batch):
    req = urllib.request.Request(RPC, data=json.dumps(batch).encode(),
                                 headers={"content-type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=120))


def latest():
    return int(rpc([{"jsonrpc": "2.0", "id": 1, "method": "eth_blockNumber",
                     "params": []}])[0]["result"], 16)


def dec_feed(raw):
    raw = raw[2:]
    v = int(raw[0:64], 16)
    d = int(raw[64:128], 16)
    if d >= 2 ** 255:
        d -= 2 ** 256
    ts = int(raw[128:192], 16)
    return v, d, ts


def sample(blocks):
    out = {}
    CH = 60
    for i in range(0, len(blocks), CH):
        chunk = blocks[i:i + CH]
        bs = rpc([{"jsonrpc": "2.0", "id": j, "method": "eth_getBlockByNumber",
                   "params": [hex(b), False]} for j, b in enumerate(chunk)])
        cx = rpc([{"jsonrpc": "2.0", "id": j, "method": "eth_call",
                   "params": [{"to": FTSO, "data": SEL + XRP + "0" * 22}, hex(b)]}
                  for j, b in enumerate(chunk)])
        cf = rpc([{"jsonrpc": "2.0", "id": j, "method": "eth_call",
                   "params": [{"to": FTSO, "data": SEL + FLR + "0" * 22}, hex(b)]}
                  for j, b in enumerate(chunk)])
        bs = {r["id"]: r for r in bs}
        cx = {r["id"]: r for r in cx}
        cf = {r["id"]: r for r in cf}
        for j, b in enumerate(chunk):
            try:
                bt = int(bs[j]["result"]["timestamp"], 16)
                out[b] = (bt, dec_feed(cx[j]["result"]), dec_feed(cf[j]["result"]))
            except Exception:
                pass
        print("  ...%d/%d" % (min(i + CH, len(blocks)), len(blocks)), flush=True)
    return out


def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(len(xs) * p / 100))]


def rel(x, f):
    # Exactly Quote.convert(1e6, XRP@6dp, 6, FLR@8dp, 18): exponent = (18+8)-(6+6) = 14.
    return (10 ** 6 * x[0] * 10 ** 14) // f[0]


if __name__ == "__main__":
    span = int(sys.argv[1]) if len(sys.argv) > 1 else 40000
    stride = int(sys.argv[2]) if len(sys.argv) > 2 else 200
    tip = latest()
    blocks = list(range(tip - span, tip + 1, stride))
    print("sampling %d blocks, %d..%d stride %d" % (len(blocks), blocks[0], blocks[-1], stride),
          flush=True)
    data = sample(blocks)
    ks = sorted(data)
    print("got %d blocks" % len(ks), flush=True)

    agex = [data[b][0] - data[b][1][2] for b in ks]
    agef = [data[b][0] - data[b][2][2] for b in ks]
    print("XRP leg signed age (block.ts - feed.ts): min %d p50 %d p99 %d max %d"
          % (min(agex), pct(agex, 50), pct(agex, 99), max(agex)))
    print("FLR leg signed age:                      min %d p50 %d p99 %d max %d"
          % (min(agef), pct(agef, 50), pct(agef, 99), max(agef)))
    print("XRP readings with feed AHEAD of block: %d/%d" % (sum(1 for a in agex if a < 0), len(agex)))
    print("FLR readings with feed AHEAD of block: %d/%d" % (sum(1 for a in agef if a < 0), len(agef)))

    t0 = data[ks[0]][0]
    t1 = data[ks[-1]][0]
    print("wall span sampled: %d s (%.2f h)" % (t1 - t0, (t1 - t0) / 3600.0))

    series = [(data[b][0], rel(data[b][1], data[b][2])) for b in ks]
    for W in (300, 3600, 6 * 3600, 24 * 3600):
        moves = []
        for i, (ti, ri) in enumerate(series):
            cand = [r for (t, r) in series[:i + 1] if t <= ti - W]
            if not cand:
                continue
            r0 = cand[-1]
            if r0 == 0:
                continue
            moves.append((ri - r0) * 10000.0 / r0)  # signed, bips
        if moves:
            up = [m for m in moves if m > 0] or [0]
            dn = [-m for m in moves if m < 0] or [0]
            print("horizon %6ds n=%3d |move| p50 %7.1f p99 %8.1f max %8.1f bips "
                  "| max UP %8.1f (latch too low) | max DOWN %8.1f (rule bricked)"
                  % (W, len(moves), pct([abs(m) for m in moves], 50),
                     pct([abs(m) for m in moves], 99), max(abs(m) for m in moves),
                     max(up), max(dn)))
