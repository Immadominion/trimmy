#!/usr/bin/env python3
"""Measure the XRP/FLR relative-price move over maxFeedAge-sized windows on Coston2,
and the cross-leg timestamp skew between the two allowlisted feeds.

Both quantities are read exactly as the contract sees them: eth_call pinned to a block,
paired with that block's own timestamp.
"""
import json, sys, urllib.request

RPC = "https://coston2-api.flare.network/ext/C/rpc"
FTSO = "0xC4e9c78EA53db782E28f28Fdf80BaF59336B304d"
XRP = "015852502f55534400000000000000000000000000"
FLR = "01464c522f55534400000000000000000000000000"
SEL = "0x93e9f806"

def rpc(batch):
    req = urllib.request.Request(RPC, data=json.dumps(batch).encode(),
                                 headers={"content-type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=60))

def latest():
    return int(rpc([{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}])[0]["result"],16)

def dec_feed(raw):
    raw = raw[2:]
    v = int(raw[0:64],16)
    d = int(raw[64:128],16)
    if d >= 2**255: d -= 2**256
    ts = int(raw[128:192],16)
    return v,d,ts

def sample(blocks):
    """returns dict block -> (btime, xrp(v,d,ts), flr(v,d,ts))"""
    out = {}
    CH = 100
    for i in range(0, len(blocks), CH):
        chunk = blocks[i:i+CH]
        bs = rpc([{"jsonrpc":"2.0","id":j,"method":"eth_getBlockByNumber","params":[hex(b),False]}
                  for j,b in enumerate(chunk)])
        cx = rpc([{"jsonrpc":"2.0","id":j,"method":"eth_call",
                   "params":[{"to":FTSO,"data":SEL+XRP+"0"*22}, hex(b)]} for j,b in enumerate(chunk)])
        cf = rpc([{"jsonrpc":"2.0","id":j,"method":"eth_call",
                   "params":[{"to":FTSO,"data":SEL+FLR+"0"*22}, hex(b)]} for j,b in enumerate(chunk)])
        bs={r["id"]:r for r in bs}; cx={r["id"]:r for r in cx}; cf={r["id"]:r for r in cf}
        for j,b in enumerate(chunk):
            try:
                bt = int(bs[j]["result"]["timestamp"],16)
                out[b] = (bt, dec_feed(cx[j]["result"]), dec_feed(cf[j]["result"]))
            except Exception:
                pass
    return out

def pct(xs,p):
    xs=sorted(xs); return xs[min(len(xs)-1,int(len(xs)*p/100))]

def rel(x, f):
    # WC2FLR wei per 1 whole FXRP:  1e6 * xv * 10**14 / fv   (exponent = (18+8)-(6+6) = 14)
    return (10**6 * x[0] * 10**14) // f[0]

if __name__ == "__main__":
    span = int(sys.argv[1]) if len(sys.argv)>1 else 1200   # blocks back
    tip = latest()
    blocks = list(range(tip-span, tip+1))
    print(f"sampling blocks {blocks[0]}..{blocks[-1]}", flush=True)
    data = sample(blocks)
    print(f"got {len(data)} blocks", flush=True)
    ks = sorted(data)

    # cross-leg timestamp skew, and per-leg age
    skews=[]; agex=[]; agef=[]
    for b in ks:
        bt,x,f = data[b]
        skews.append(abs(int(x[2])-int(f[2])))
        agex.append(bt-x[2]); agef.append(bt-f[2])
    print("cross-leg |ts_xrp - ts_flr| (s): p50 %d p90 %d p99 %d max %d" %
          (pct(skews,50),pct(skews,90),pct(skews,99),max(skews)))
    print("XRP leg age p50 %d p90 %d p99 %d max %d" % (pct(agex,50),pct(agex,90),pct(agex,99),max(agex)))
    print("FLR leg age p50 %d p90 %d p99 %d max %d" % (pct(agef,50),pct(agef,90),pct(agef,99),max(agef)))
    print("negative XRP ages (feed ahead of block):", sum(1 for a in agex if a<0),
          "min", min(agex))
    print("negative FLR ages:", sum(1 for a in agef if a<0), "min", min(agef))

    # relative-price move over W seconds, sliding
    for W in (34, 120):
        moves=[]
        ts2b = {data[b][0]: b for b in ks}
        for b in ks:
            bt = data[b][0]
            # find the block closest to bt - W
            target = bt - W
            cand = [c for c in ks if c<=b and data[c][0] <= target]
            if not cand: continue
            c = cand[-1]
            r0 = rel(data[c][1], data[c][2]); r1 = rel(data[b][1], data[b][2])
            if r0 == 0: continue
            moves.append(abs(r1-r0)*10000/r0)
        if moves:
            print("|d rel| over %ds: n=%d p50 %.2f p90 %.2f p99 %.2f max %.2f bips" %
                  (W,len(moves),pct(moves,50),pct(moves,90),pct(moves,99),max(moves)))

    # signed worst-case: the max DOWNWARD move (what an attacker exploits) over 120s
    for W in (120,):
        down=[]
        for b in ks:
            bt=data[b][0]; target=bt-W
            cand=[c for c in ks if c<=b and data[c][0] <= target]
            if not cand: continue
            c=cand[-1]
            r0=rel(data[c][1],data[c][2]); r1=rel(data[b][1],data[b][2])
            if r0==0: continue
            down.append((r0-r1)*10000/r0)   # positive when price FELL: stale latch too high
        print("signed (stale - live)/stale over %ds: p99 %.2f max %.2f bips" % (W,pct(down,99),max(down)))
