# Trimmy — FTSO staleness measured with the contract's clock, and the exact decimals normalisation

**Date:** 2026-08-06 · **Network:** Coston2 (chainId 114) · **Status:** IN PROGRESS — first results landed

Resolves `00-critique.md` **U1**. Both prior measurements used `wallclock_of_curl − ts`; the contract
sees `block.timestamp − ts`. This document measures the latter directly.

Labels: `[Verified]` primary source / live chain · `[Measured]` computed from an experiment described
here · `[Inference]` reasoned from stated verified facts · `[Unverified]` open, experiment named.

---

## 0. Headline (preliminary, n=180)

`block.timestamp − feed.timestamp` for XRP/USD on Coston2 is **bimodal, not constant**:
**p50 = 0s**, but a long tail to **31s**. The 29-second observation in `keeper-security.md` §T4
**reproduces**. The "12/12 at exactly 6s" result was an artefact of measuring against wallclock.

_Full numbers in §2 after the expanded sample._

---

## 1. Method

`eth_call` to FtsoV2 `0xC4e9c78EA53db782E28f28Fdf80BaF59336B304d` with
`getFeedById(bytes21)` (selector `0x93e9f806`), **at pinned historical block numbers**, paired with
`eth_getBlockByNumber` for that same block's `timestamp`. This measures exactly the quantity a
deployed contract would compute, without needing C2FLR or a deployment: an `eth_call` pinned to
block N executes against block N's state with `block.timestamp` = that block's timestamp.

`[Verified]` The Coston2 public RPC `https://coston2-api.flare.network/ext/C/rpc` **serves archive
state**: `eth_call` at `latest − 500` returned a well-formed
`(0xff5a4, 6, 0x6a74a0d4)` tuple rather than a "missing trie node" error. This is what makes the
no-deploy method viable.

Script: `scratchpad/measure.py`; raw samples `scratchpad/samples.json`.

---

## 2. Preliminary distribution (n=180, three sampling strides)

| set | stride | n | min | p50 | p90 | p95 | p99 | max | mean |
|---|---|---|---|---|---|---|---|---|---|
| contiguous | 1 blk | 60 | 0 | 0 | 10.3 | 17.6 | 30.4 | **31** | 3.83 |
| stride7 | 7 blk | 60 | 0 | 0 | 8.2 | 10.0 | 20.0 | 23 | 2.30 |
| stride53 | 53 blk | 60 | 0 | 0 | 6.4 | 14.0 | 23.8 | 25 | 2.50 |
| **ALL** | — | **180** | **0** | **0** | **10.0** | **14.0** | **29.2** | **31** | **2.88** |

Histogram of age in seconds, all 180 samples:

```
0:107  1:13  2:14  3:6  4:3  5:5  6:6  8:3  9:3  10:6  11:1  12:1
13:1  14:2  15:1  17:1  18:1  23:2  25:1  29:1  30:1  31:1
```

**59% of blocks see a zero-second-old feed.** The tail is real and reaches 31s.

`[Measured]` Coston2 inter-block time over 60 contiguous blocks: min 1s, **p50 1s**, **max 25s**.
Coston2 block production is irregular. This is the mechanism behind the tail: the feed cannot be
newer than the block it is read in, so a 25-second block gap forces an age of at least ~25s at the
next block. **Feed age tracks block-gap variance, not oracle downtime.**

`[Measured]` Distinct feed-timestamp deltas within the contiguous window:
`32, 2, 1, 1, 2, 1, 1, 1, 11, 4, 1, 1, 1, 1, 18, 1, 10, 1, 1, 3, 30, 1, 3, 1, 14, 31, 1, 1, 3, 1, 7, 3, 1`
— the block-latency feed updates roughly per block when blocks are dense, and simply cannot update
during a long block gap.

---

_(expanded sample, fee check, decimals normalisation and feed-id table follow)_
