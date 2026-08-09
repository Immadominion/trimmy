# 03 — Attack: the off-chain tooling

**Date:** 2026-08-07 · **Target:** deployed code, not a spec · **Chain:** Coston2 (114),
`https://coston2-api.flare.network/ext/C/rpc` · Trimmy `0xf73a2af06b315adaa1afe2c1a6c1a6933d8a6554`

Scope: `arming/bin/arm.dart`, `arming/bin/decode.dart`, `keeper/bin/keeper.dart`,
`tools/execute_arming.py`. Every claim below is labelled. Probes written for this pass:
`arming/bin/zz_offchain_probe.dart` (ABI differential) and `arming/bin/zz_hostile.dart`
(hostile-batch generator; outputs in `/tmp/trimmy-attack/`).

---

## Summary

The lens's headline hypothesis — that the hand-rolled `encodeExecuteUserOp` gets the offset
arithmetic wrong — is **false**. It is byte-exact against `cast abi-encode` in every case tried.
The keeper's word-index decoding is also **correct**, verified field by field against a live
`ruleAt(3)`.

What is actually wrong is a consistent pattern: **the tools check the things they wrote themselves
and skip the things that come from outside.** `arm.dart` cross-checks its own encoder against
Plimsoll's decoder but never asks the chain a single validating question before emitting an
irreversible payment. `decode.dart` — whose entire premise is "no trust in whoever produced this
payment" — renders a hostile batch identically to an honest one. `keeper.dart` guards the one call
it expects to fail and nothing else. `execute_arming.py` spends the FDC fee before checking the one
thing it could check for free.

| # | Severity | What |
|---|---|---|
| OFF-1 | High | `arm.dart` hardcodes the controller; its own comment claims it resolves it |
| OFF-2 | High | `arm.dart` validates nothing about the personal account it arms against |
| OFF-3 | High | `decode.dart` never prints the *target* of a call it recognises |
| OFF-4 | High | `decode.dart` silently omits calls with <4 bytes of data, and never shows `value` |
| OFF-5 | Medium | `decode.dart` certifies a zero-executor-fee memo as "matches this batch" |
| OFF-6 | Medium | `arm.dart`'s executor-fee guard is `>0`; the real floor is 100000 UBA |
| OFF-7 | Medium | `decode.dart` crashes on a truncated `approve` instead of refusing |
| OFF-8 | Medium | `keeper.dart` daemon dies permanently on one failed read or one lost race |
| OFF-9 | Medium | `keeper.dart` never claims after `cancelAll()`, though the contract allows it |
| OFF-10 | Medium | `keeper.dart` nonce at `latest`, shares its default key with `execute_arming.py` |
| OFF-11 | Medium | `execute_arming.py` links nothing to the payment before spending; exits 0 on revert |
| OFF-12 | Low | `decode.dart` renders every amount at 6 decimals regardless of token |
| OFF-13 | Low | `decode.dart` expiry wraps through signed int64 |
| OFF-14 | Info | `keeper.dart` has no code path to attach `msg.value` for an FTSO fee |

---

## Verified negatives — stated first, because they matter

### N-1. `encodeExecuteUserOp` is correct. `[Verified]`

`arming/bin/arm.dart:50-85`. Copied verbatim into `arming/bin/zz_offchain_probe.dart` and
diffed against `cast abi-encode "f((address,uint256,bytes)[])"` for: 0 calls, 1 call with empty
calldata, 1 call with 4 bytes, 1 call with 33 bytes and non-zero value, 2 calls, 3 calls with a
mid-batch empty-calldata element and a 70-byte tail.

**All six match byte for byte.** Both suspicious pieces are right:

- `p.abiWord(BigInt.from(96))` (`arm.dart:59`) — the tuple head is exactly three words, so 96 is
  the correct in-tuple offset to `bytes`.
- `var cursor = calls.length * 32` then `cursor += e.length` (`arm.dart:65-70`) — element offsets
  are relative to the start of the array body, which is what this computes.

Empty calldata is also canonical: `p.abiDynamicBytes` (plimsoll_core `abi.dart:132-139`) emits the
length word and zero padding bytes, which is what solc does.

### N-2. `keeper.dart ruleAt` word indices are all correct. `[Verified]`

`keeper/bin/keeper.dart:127-150` against `Trimmy.sol:69-101` (24 fields) and a live
`cast call 0xf73a…6554 "ruleAt(uint256)" 3`:

| field | keeper index | live word | value | matches `Trimmy.Rule` |
|---|---|---|---|---|
| `account` | 0 | w0 | `0x07a76b5c…` | yes |
| `epoch` | 1 | w1 | 0 | yes |
| `verb` | 4 | w4 | 1 = `DEPOSIT_VAULT` | yes |
| `trigger` | 6 | w6 | 2 = `SCHEDULE` | yes |
| `active` | 7 | w7 | 0 | yes |
| `totalSellAmount` | 8 | w8 | 1000000 | yes |
| `spent` | 10 | w10 | 1000000 | yes |
| `nextEligibleAt` | 13 | w13 | 0x6a755d85 | yes |
| `expiry` | 14 | w14 | 0x6a7e9164 | yes |
| `keeperFeeFlat` | 16 | w16 | 0x24b8 = 9400 | yes |
| `pendingShares` | 19 | w19 | 0 | yes |
| `claimableAt` | 22 | w22 | 0 | yes |

No off-by-one anywhere. The enum orders match too (`Trimmy.sol:34-44` vs `keeper.dart:58-59` and
`decode.dart:28-29`).

### N-3. The 32-byte memo comparison is correct and `sublistView` is safe. `[Verified]`

`decode.dart:130` is unreachable with a short memo: `decode.dart:122-125` rejects
`memo.length != 42` and exits 1 first. Same in `arm.dart:202-204` before `arm.dart:224`. Constant
time is irrelevant here (the commitment is public). Measured: `--memo FE00` → "MEMO REJECTED: 2
bytes, must be 42", exit 1.

### N-4. Selectors are right. `[Verified]`

`cast sig "executeUserOp((address,uint256,bytes)[])"` = `0x2b2ee783` = the hardcode at
`arm.dart:72-76`. `cast sig "arm((uint8,…,uint128))"` = `0xc33d4cc3` = the literal at
`decode.dart:170`. `approve(address,uint256)` = `0x095ea7b3` = `decode.dart:164`.

---

## OFF-1 [High] — `arm.dart` hardcodes the controller while its comment claims it resolves it

**File:** `arming/bin/arm.dart:259`, comment at `:263-265`.

```dart
const controller = '0x434936d47503353f06750Db1A444DBDC5F0AD37c';   // :259
…
// Rule 2: resolve, never hardcode. Assert the controller we are about to arm against is the
// one the AssetManager itself points at — two are live on Coston2 with identical ABIs, and
// arming against the wrong one sets an allowance on an empty account, permanently.
```

`[Verified]` The comment describes an assertion. Grep for `getSmartAccountManager`, `balanceOf`,
`getCode` in `arm.dart` returns nothing. The only chain reads are `getPersonalAccount(string)`
(`:266-271`) and `getNonce(address)` (`:274-277`), both issued *to the hardcoded constant*.

`AGENTS.md` rule 2 is explicit: *"The canonical one is whatever `AssetManager.getSmartAccountManager()`
returns, resolved at runtime. **Never hardcode it.**"*

`[Measured]` The call the rule names exists and works today:

```
$ cast call 0xc1Ca88b937d0b528842F95d5731ffB586f4fbDFA "getSmartAccountManager()(address)" --rpc-url $R
0x434936d47503353f06750Db1A444DBDC5F0AD37c
$ cast call 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019 \
    "getContractAddressByName(string)(address)" MasterAccountController --rpc-url $R
0x434936d47503353f06750Db1A444DBDC5F0AD37c
```

**Failure scenario.** The constant is correct on Coston2 *today*. It is not an assertion, so
nothing detects the day it stops being correct: a controller migration, or the same file run against
Coston/Songbird/mainnet where the value differs. Rule 2's stated consequence then applies in full —
the allowance lands on an account the real controller does not drive, every `execute()` reverts on
`transferFrom` forever, and the XRP is already gone. This is a permanent silent failure that the
code's own comment promises to prevent and does not.

**Fix.** Replace `:259` with a runtime read of `getSmartAccountManager()` from
`AssetManagerFXRP`, itself resolved from `FlareContractRegistry`, and `throw StateError` if the
result does not match a pinned expectation. Two `eth_call`s, both already trivially available via
the `_call` helper at `:325`.

---

## OFF-2 [High] — `arm.dart` validates nothing about the personal account it is about to arm

**File:** `arming/bin/arm.dart:248` (`--xrpl` taken raw), `:266-277`, `:298-306`.

`[Verified]` `arm.dart` takes `--xrpl` as an opaque string, ABI-encodes it (`_abiString`, `:335`),
resolves a personal account, and builds an irreversible 42-byte memo. It never checks that the
string is a well-formed XRPL address, that the resolved account holds enough FXRP, or that it has
code deployed.

`[Measured]` Live reads against the canonical controller `0x434936d4…`:

| `--xrpl` value | resolved personal account | FXRP balance | code |
|---|---|---|---|
| `rDE4JUm2jaue31VwidRXWuWzf5dQkUxcsB` (correct) | `0x07A76b5C3d03F5BfF4cb3E043b1D17a1B40920bf` | 7400000 (7.4) | ~291 bytes |
| `rDE4JUm2jaue31VwidRXWuWzf5dQkUxcs8` (last char typo) | `0x5d21ed679feFcD8be81147D19544b7E6E056F013` | **0** | **none** |
| `NOT_AN_XRPL_ADDRESS` | `0xDcc8E14F18E8026DCc5E4d525Fe82A05A73c9B89` | **0** | **none** |
| `""` (empty string) | `0x43343c9d529D483A5d0ca42BbeadFB52635adfB0` | **0** | **none** |

`getPersonalAccount` is a pure hash — it returns a plausible-looking address for the empty string.
There is no error to notice.

**Failure scenario.** A user mistypes one base58 character of their XRPL address (or a front end
passes an unnormalised one). `arm.dart` prints a complete, confident payment plan and a 42-byte
memo. The user signs in Xaman. The mint succeeds, the batch executes, the `approve` lands on
`0x5d21ed67…` which holds zero FXRP. Every subsequent `execute()` reverts on `transferFrom` for the
life of the rule. The XRP is at the Core Vault and no code path recovers it. `arm.dart:155` says
"Rule 7 — unknown means do not proceed. Every check here is a refusal, not a warning"; the checks it
actually performs are (a) memo length, (b) executor fee `> 0`, (c) the memo commits to the operation
it just built — all internal self-consistency.

**Worse:** `arm.dart` holds an open `FlareClient` and never simulates the batch. A single
`eth_call` of the `arm()` calldata from the resolved personal account would catch every
`_validate()` rejection (`Trimmy.sol` `arm` → `_validate`) before the money moves. That call is not
made.

**Fix.** Before returning from `main`: assert `balanceOf(pa) >= allowance`; assert
`eth_getCode(pa)` is non-empty *or* explicitly document that first-use deployment is expected;
`eth_call` the `arm()` calldata with `from: pa` and refuse on revert. All three use machinery already
present in the file.

---

## OFF-3 [High] — `decode.dart` never prints the target of a call it recognises

**File:** `arming/bin/decode.dart:58-66` (`_describeApprove`), `:68-90` (`_describeArm`),
`:160-183` (the dispatch loop).

`decode.dart`'s premise (`:9-15`): *"a compromised front end takes its own decoder with it… this is
a **standalone program with no network access**… it will do that for a payment produced by anyone,
including one produced by an attacker. On stage this decodes a batch we did not generate."*

`[Verified]` `_describeApprove` prints the **spender** and the amount. It never prints `c.target` —
the token being approved. `_describeArm` prints the rule parameters. It never prints `c.target` —
the contract being armed. `c.target` appears exactly once in the whole file, in the *unrecognised*
branch at `:174`.

**Proof of concept.** `arming/bin/zz_hostile.dart` builds two batches with the same sender, nonce
and shape:

- `honest` — `[FXRP.approve(TRIMMY, 1009400), TRIMMY.arm(…)]`
- `hostile-target` — `[FXRP.approve(0x…dEaDbEeF, 1009400), 0x…dEaDbEeF.arm(…)]`

Both were given valid 42-byte memos committing to their own preimages. `decode.dart` output, diffed:

```
  1. APPROVE
-    lets  0xf73a2af06b315adaa1afe2c1a6c1a6933d8a6554
+    lets  0x00000000000000000000000000000000deadbeef
     spend 1.0094 FXRP of yours
     note  this is an allowance, not a transfer. It is capped at this exact
           amount, and nothing may spend more than it.

  2. ARM A RULE
     action     DEPOSIT_VAULT
     …
```

That single address line is the **entire** difference. Both exit 0. Both print
`memo : matches this batch`. The second call goes to `0x…dEaDbEeF`, not Trimmy, and is rendered as
`2. ARM A RULE` with no hint of that. The `touchesFxrp` backstop at `:180-183` is satisfied by the
hostile `approve`, so no note is printed either.

**Failure scenario.** Hostile front end emits `[FXRP.approve(EVIL, N), EVIL.arm(<plausible params>)]`.
The user runs the independent decoder exactly as instructed. It prints a reassuring, structurally
identical report and appends *"note this is an allowance, not a transfer. It is capped at this exact
amount, and nothing may spend more than it"* — a sentence that is true and completely beside the
point, because `EVIL` will spend all of it. The user signs. This is the failure the program exists
to prevent, and the program does not detect it.

**Fix.** Print `c.target` on every branch. Then, since this tool is Trimmy-specific, hard-fail
(exit 1, "DO NOT SIGN") when the `approve` target is not the known FXRP address, when the `approve`
spender is not the `arm` target, or when the `arm` target is not the expected Trimmy address passed
as a required `--trimmy` argument.

---

## OFF-4 [High] — `decode.dart` silently omits calls with <4 bytes of data, and never shows `value`

**File:** `arming/bin/decode.dart:160-179`.

```dart
for (final c in calls) {
  final data = c.data;
  if (data.length >= 4) {          // :162
    …
  }                                 // no else
}
```

`[Verified]` A call whose calldata is 0–3 bytes produces **no output at all** — not even the
"UNRECOGNISED" warning, which lives inside the `if`. Separately, `c.value` is never read anywhere in
the file, although `plimsoll_core` exposes it (`SimulatedCall.valueOrZero`, used by
`userop.dart:228`).

**Proof of concept.** `/tmp/trimmy-attack/hidden-value.hex` —
`[FXRP.approve(TRIMMY, 1009400), TRIMMY.arm(…), (0x…dEaDbEeF, value = 10e18, data = 0x)]`:

```
  This payment will do 3 thing(s):

  1. APPROVE …
  2. ARM A RULE …
                       <- nothing. exit 0.
```

The count says three. Two are described. The third — a bare native-value transfer of 10 FLR to an
attacker — is invisible. Adding calls with 1-, 2- or 3-byte calldata hides arbitrarily many of them.

**Failure scenario.** Any batch the front end appends a value-bearing call to is under-reported.
The tool volunteers the count, which makes the omission look like a rendering gap rather than a
hidden call, and it exits 0 either way.

**Fix.** Move the `UNRECOGNISED` block to an unconditional `else`, and print
`value ${c.valueOrZero}` for every call — refusing outright when it is non-zero, since no legitimate
Trimmy arming batch carries native value.

---

## OFF-5 [Medium] — `decode.dart` certifies a zero-executor-fee memo as "matches this batch"

**File:** `arming/bin/decode.dart:118-141` vs `arming/bin/arm.dart:206-221`.

`arm.dart:206-221` calls the zero-executor-fee payment *"the single most expensive way to get an
irreversible payment wrong, because every protocol-level check passes"* and makes it a hard refusal.

`[Verified]` `decode.dart` checks the memo's length (`:122`), its opcode byte (`:126`), and bytes
10..42 against the commitment (`:130-139`). Bytes 2..10 — the `executorFeeUBA` — and byte 1 — the
wallet id — are never read or displayed.

**Proof of concept.** `[Measured]` The honest memo is
`0xfe` `00` `0000000000002710` `1af948f8…` (opcode, walletId, fee = 10000, hash). Zeroing bytes 2..10:

```
$ dart run bin/decode.dart --file honest.hex --memo-file honest.memo-zerofee
  commitment     : 0x1af948f8b73ed315a2e4979797cb6c47c99702f393e38c2eda192f9ed6b004f8
  memo           : matches this batch
  …
exit 0
```

**Failure scenario.** A front end that wants a payment to quietly die emits a correct batch with
`executorFeeUBA = 0`. `decode.dart` — the tool the user is told to trust *precisely because the front
end may be hostile* — passes it. The XRP leaves the user's control and sits at the Core Vault
indefinitely, which is exactly the outcome the repo already reproduced with XRPL
`C122663D…326104` (`arm.dart:209-211`).

**Fix.** Decode and print the fee, and refuse when it is zero. Ideally accept an optional
`--min-executor-fee` and refuse below it, mirroring OFF-6.

---

## OFF-6 [Medium] — `arm.dart`'s executor-fee guard is `>0`; the real floor is 100000 UBA

**File:** `arming/bin/arm.dart:215-221`, default at `:256`.

```dart
if (executorFeeUBA <= BigInt.zero) {
  throw StateError(
    'REFUSING TO ARM: executorFeeUBA is zero. …'
    'Pass --executor-fee at or above getDirectMintingExecutorFeeUBA().');
}
```

`[Verified]` The message names `getDirectMintingExecutorFeeUBA()`. The condition tests `> 0`.
`arm.dart` never calls that function.

`[Measured]`

```
$ cast call 0xc1Ca88b937d0b528842F95d5731ffB586f4fbDFA \
    "getDirectMintingExecutorFeeUBA()(uint256)" --rpc-url $R
100000 [1e5]
```

**Failure scenario.** `dart run bin/arm.dart --xrpl r… --executor-fee 1` passes the guard and emits
a payment. Anything in `[1, 99999]` does. That payment reproduces the *exact* failure the comment
above the guard describes — the executor earns less than its floor, nobody volunteers, the money
sits. The refusal is a strawman: it rejects the one value a careless user would never pass and
accepts the 99999 values that fail identically. Note the *default* is `0` (`:256`), so the guard
does correctly stop the no-argument invocation — but it stops it for the wrong reason.

**Fix.** Read `getDirectMintingExecutorFeeUBA()` from the AssetManager (resolved per OFF-1) and
compare against it.

---

## OFF-7 [Medium] — `decode.dart` crashes on a truncated `approve` instead of refusing

**File:** `arming/bin/decode.dart:59-60` (needs ≥68 bytes), `:69-89` (needs ≥452 bytes), guarded only
by `:162` (`>= 4`).

**Proof of concept.** `/tmp/trimmy-attack/short-approve.hex` — one call, `data = 0x095ea7b3`:

```
  memo           : matches this batch
  This payment will do 1 thing(s):

Unhandled exception:
RangeError (start): Invalid value: Not in inclusive range 0..4: 16
#0      RangeError.checkValidRange
#1      new Uint8List.sublistView
#2      _describeApprove (…/arming/bin/decode.dart:59:39)
#3      main (…/arming/bin/decode.dart:165:17)
```

Exit code 255 `[Measured]`.

**Failure scenario.** The output the user sees is: *"memo matches this batch"*, *"this payment will
do 1 thing"*, then a Dart stack trace. Nothing says DO NOT SIGN. `decode.dart:93-94` explicitly
reasons about exit codes — *"Every refusal below calls `exit()` explicitly, so a shell guard or CI
step can actually act on it"* — and this path bypasses that design entirely. A malformed `arm` call
(any length between 4 and 451 bytes) fails the same way at `_word`.

**Fix.** Length-check before each describer (`>= 68` for approve, `>= 452` for arm) and route
short/unknown calls to the existing refusal branch.

---

## OFF-8 [Medium] — the keeper daemon dies permanently on one failed read or one lost race

**File:** `keeper/bin/keeper.dart:227-283` (`sweep`), `:331-337` (the daemon loop), `:219-222`.

`[Verified]` The only `try` in the file is inside `simulate` (`:163-175`). `sweep` and `main`'s
`do…while` have none. Every other `await` is unguarded: `ruleCount` (`:121`), `ruleAt` (`:128`),
`epochOf` (`:155`), `prepareTransaction` (`:192`), `getTransactionCount` (`:195`),
`sendRawTransaction` (`:217`), `waitForReceipt` (`:218`) — plus the deliberate
`throw StateError('reverted after mining: …')` at `:221`.

**Proof of concept.** `[Measured]` A single bad read, in *interval* mode:

```
$ TRIMMY_ADDRESS=0x000000000000000000000000000000000000dEaD dart run bin/keeper.dart --interval 5
Trimmy keeper
  interval : 5s

Unhandled exception:
RangeError (length): Invalid value: Valid value range is empty: 0
#1      Keeper._word (…/keeper/bin/keeper.dart:115:38)
#2      Keeper.ruleCount (…/keeper/bin/keeper.dart:122:12)
#3      Keeper.sweep (…/keeper/bin/keeper.dart:228:19)
#4      main (…/keeper/bin/keeper.dart:332:17)
```

The process is gone before the second sweep. There is no supervisor in the repo.

**Failure scenario, the realistic one.** The file's own header (`:13-17`) argues that reverts are
*"the COMMON case, not the exceptional one"*. A rule passes `simulate()` at block N and is broadcast;
another keeper (the design is permissionless — `:8`, "Anyone can run this") lands `execute` first, or
the FTSO feed moves within the inclusion window. The transaction mines and reverts. `:219-222`
throws. Nothing catches it. **The keeper that lost one race stops running forever**, and only a
human notices. Baseline liveness for a product whose whole promise is unattended execution.

Transient RPC is the other trigger and it is not hypothetical: `[Measured]` during this review a
routine `cast call` against `coston2-api.flare.network` failed with
`Error #2: connection closed` on the third sequential request.

**Fix.** Wrap the per-rule body and the whole sweep in `try/catch`, log, and continue to the next
interval. `simulate`'s `on Object catch` already establishes the pattern; it just is not applied
where losing costs liveness.

---

## OFF-9 [Medium] — the keeper never claims after `cancelAll()`, though the contract allows it

**File:** `keeper/bin/keeper.dart:236-240` vs `contracts/src/Trimmy.sol:543-566`, `:637-641`.

```dart
// keeper.dart:236 — runs BEFORE the claim branch at :242
if (rule.active && rule.epoch != await epochOf(rule.account)) {
  skipped++;
  _log(i, 'skip', 'stale epoch (cancelAll)');
  continue;
}
```

`[Verified]` Three facts that combine badly:

1. `cancelAll()` (`Trimmy.sol:637-641`) bumps `epochOf[msg.sender]` and **leaves `r.active == true`**
   on every rule. It touches no rule storage at all.
2. `claim()` (`Trimmy.sol:543-566`) does **not** call `_load` and does **not** check the epoch. Its
   only gates are `verb == EXIT_VAULT`, `pendingShares != 0`, and `block.timestamp >= claimableAt`.
   It is still perfectly executable after `cancelAll()` — deliberately so, since the shares are
   already the user's.
3. The keeper's epoch guard sits at `:236`, *before* the `maybeClaimable` branch at `:242`, and
   `continue`s.

**Failure scenario.** A user has an `EXIT_VAULT` rule that has queued shares with the vault
(`pendingShares > 0`, `claimableAt` in the future). Something spooks them and they hit the panic
button, `cancelAll()`. The keeper now skips that rule on every sweep with `stale epoch (cancelAll)`
and never calls `claim(ruleId)`. The user's assets stay in the vault's withdrawal queue
indefinitely, unclaimed. The contract would have let the keeper claim them at any point. Note that
the *targeted* `cancel(ruleId)` path is fine — it sets `active = false`, so the guard's
`rule.active` term is false and the claim branch is reached.

**Fix.** Evaluate `maybeClaimable` before the epoch guard, or narrow the guard to
`rule.active && !rule.maybeClaimable && rule.epoch != …`.

---

## OFF-10 [Medium] — nonce at `latest`, and the default key is shared with `execute_arming.py`

**File:** `keeper/bin/keeper.dart:195`, `:299-300`; `tools/execute_arming.py:55`.

```dart
final nonce = await client.getTransactionCount(keeperAddress);   // :195
```

`[Verified]` The SDK's signature is
`getTransactionCount(EthAddress address, {BlockTag block = BlockTag.latest})`
(`sdk/packages/flare_network/lib/src/rpc/flare_client.dart:278-284`) — the default is **latest**.
The SDK's own broadcast tests pass `BlockTag.pending` explicitly
(`test/integration/broadcast_test.dart:152-155` and `:188-191`), which is the pattern
`keeper.dart:20-24` claims to be following.

**Within one process this is safe** — `send` awaits `waitForReceipt` (`:218`), so two rules in a
sweep are strictly serialised. The lens's "two rules in one sweep" hypothesis is a **negative**.

**The real collision is across processes.** `[Verified]` `keeper.dart:299-300` falls back to
`COSTON2_TEST_KEY` / `COSTON2_TEST_ADDRESS`, and `tools/execute_arming.py:55` calls
`pipeline.coston2_key()` — the same repo test account, which then does `cast send` twice
(`pipeline.py:209` and `:349`).

**Failure scenario.** An operator runs `keeper.dart --interval 15` and, in another shell, runs
`execute_arming.py` to push an arming payment through FDC — the documented workflow. Both build
transactions from the same address. The keeper reads nonce *n* at `latest` while the Python
`cast send` already has *n* in the mempool. `sendRawTransaction` throws `nonce too low`, which per
**OFF-8** is uncaught and **kills the keeper daemon**. Two keeper instances on the same key do the
same.

**Fix.** `block: BlockTag.pending`, and refuse to start if `KEEPER_ADDRESS` equals the account the
arming tools use.

---

## OFF-11 [Medium] — `execute_arming.py` verifies nothing before spending, and exits 0 on a revert

**File:** `tools/execute_arming.py:56-101`; `plimsoll/tool/gate3/pipeline.py:167-361`.

`[Verified]` The script reads `--preimage-file` into `data` (`:61-62`) and submits it at step
`[4/4]`. Between reading it and spending money it does:

- **no** `keccak256(data)` comparison against the memo carried by the attested XRPL payment;
- **no** check that `data` is a decodable `PackedUserOperation` (a 42-byte memo file passed by
  mistake sails through `bytes.fromhex`);
- **no** check that the payment's `sender` field matches anything.

The FDC request fee is paid at step `[2/4]` (`:84` → `pipeline.request_attestation`, which does
`cast send … --value fee`), and the mismatch is only discovered on chain at `[4/4]`, after up to
2400 s of polling (`pipeline.wait_for_proof`, `pipeline.py:231`). The memo is in the payment the
proof attests; comparing it locally costs nothing and would happen before the fee.

`[Verified]` Second defect, worse for automation: `pipeline.execute_direct_minting`
(`pipeline.py:340-360`) *returns* `{"status": "reverted", …}` rather than raising — a deliberate
choice for Plimsoll's own experiments. `execute_arming.py:99-101` prints it and unconditionally
`return 0`:

```python
outcome = pipeline.execute_direct_minting(proof, data, key)
print(f"      outcome: {outcome}")
return 0
```

**Failure scenario.** An operator wires this into a script or a runbook step. The mint reverts —
wrong preimage, wrong controller, stale nonce, `CustomInstructionHashMismatch`. The process exits
**0**. Every downstream step proceeds as though the rule were armed. This is the same exit-code
concern `decode.dart:93-94` calls out explicitly and gets right; the Python tool does not.

**Fix.** (a) Before step `[2/4]`, fetch the XRPL transaction's memo and refuse unless
`memo[10:42] == keccak256(data)`. (b) `return 0 if outcome["status"] == "success" else 1`.

---

## OFF-12 [Low] — `decode.dart` renders every amount at 6 decimals regardless of token

**File:** `arming/bin/decode.dart:51-56` (`_fxrpAmount`, hardcoded 6dp), applied at `:63`, `:78`,
`:79`, `:80`, `:89`.

`[Verified]` `_describeArm` prints `totalSellAmount`, `partSellAmount`, `minOutAbsolute`,
`keeperFeeFlat` and `keeperFeeBudget` through `_fxrpAmount` while printing the token as a bare id
(`sell up to … (token #${w(0)})`). `minOutAbsolute` and the keeper fees are denominated in the
**buy** token (`Trimmy.sol` `_settle` pays the keeper out of `proceedsToken`), so they get the wrong
scale even when the sell token is FXRP.

`[Measured]` `cast call 0xf73a…6554 "tokenAt(uint8)" 1` returns decimals `0x12` = 18 (WC2FLR);
`tokenAt(0)` returns `0x06` (FXRP).

**Failure scenario.** A rule selling 1 WC2FLR (`1e18`, `sellTokenId = 1`) renders as
`sell up to 1000000000000 (token #1)`. A user reading the independent decoder to check "am I selling
one token or a million" gets a 10^12 error. `AGENTS.md` rule 8 is specifically about not mixing unit
systems.

**Fix.** Take the decimals from the token id (a two-entry table, or a required `--decimals` pair),
and label the unit rather than always printing "FXRP".

---

## OFF-13 [Low] — expiry wraps through signed int64

**File:** `arming/bin/decode.dart:86-87`.

```dart
final expiry = bw(9).toInt();
stdout.writeln('     expires    ${DateTime.fromMillisecondsSinceEpoch(expiry * 1000, isUtc: true)}');
```

`[Measured]` `/tmp/trimmy-attack/huge-expiry.hex` with `expiry = 2^64 - 1` prints:

```
     expires    1969-12-31 23:59:59.000Z
```

`BigInt.toInt()` truncates to the low 64 bits *signed*, so any `expiry >= 2^63` renders as a date in
the past. Related cosmetic defect in the same run: the item numbers are hardcoded (`1.` for approve,
`2.` for arm, `decode.dart:61` and `:75`), so this single-call batch printed `2. ARM A RULE`, and a
batch of three approves would print `1.` three times.

**Fix.** Range-check `bw(9)` against a sane bound and print the raw integer alongside the date.

---

## OFF-14 [Informational] — the keeper has no code path to pay a non-zero FTSO fee

**File:** `keeper/bin/keeper.dart:193` and `:197-211` vs `contracts/src/Trimmy.sol:656-673`.

`[Verified]` `execute()` is `payable` and `_readFeeds` reverts `InsufficientFeeValue(msg.value, fee)`
when `msg.value < calculateFeeById(sell) + calculateFeeById(buy)`. The keeper builds
`TransactionRequest(from:, to:, data:)` with no `value` and invokes `cast mktx` without `--value`.
`simulate` likewise passes no value.

`[Measured]` Today the point is moot: on Coston2 `FtsoV2.calculateFeeById` returns `0` for both
`XRP/USD` (`0x015852502f55534400…`) and `FLR/USD` (`0x01464c522f55534400…`).

**Failure scenario.** If Flare ever prices these feeds, `simulate` starts returning
`InsufficientFeeValue` for every rule and the keeper degrades to silent, total inaction — reported as
an ordinary skip. It fails safe rather than expensively, which is why this is informational, but the
fee is read at the top of `_readFeeds` and there is no plumbing to satisfy it.

---

## Reproduction

```bash
export PATH=$HOME/.foundry/bin:$PATH
R=https://coston2-api.flare.network/ext/C/rpc

# N-1: ABI differential (compare against `cast abi-encode "f((address,uint256,bytes)[])"`)
cd arming && dart run bin/zz_offchain_probe.dart

# OFF-3/4/5/7/13: hostile batches
dart run bin/zz_hostile.dart                       # -> /tmp/trimmy-attack/*.hex, *.memo
for c in honest hostile-target hidden-value short-approve huge-expiry; do
  dart run bin/decode.dart --file /tmp/trimmy-attack/$c.hex --memo-file /tmp/trimmy-attack/$c.memo
  echo "exit=$?"
done

# OFF-2: personal-account resolution has no validation
C=0x434936d47503353f06750Db1A444DBDC5F0AD37c
for a in rDE4JUm2jaue31VwidRXWuWzf5dQkUxcsB rDE4JUm2jaue31VwidRXWuWzf5dQkUxcs8 ""; do
  cast call $C "getPersonalAccount(string)(address)" "$a" --rpc-url $R
done

# OFF-8: one bad read kills the daemon
cd ../keeper
TRIMMY_ADDRESS=0x000000000000000000000000000000000000dEaD dart run bin/keeper.dart --interval 5
```
