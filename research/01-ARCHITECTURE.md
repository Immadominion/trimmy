# Trimmy — architecture

**Date:** 2026-08-07 · **Status:** normative. This supersedes the execution model in
`keeper-security.md` §3, `rule-taxonomy.md` §3, and `fcc-extension.md` §5.6–5.7, all three of which
were written before `onlyController` was measured.

Evidence labels follow the repo convention: `[Verified]` primary source or live chain read,
`[Measured]` computed from a stated experiment, `[Inference]` reasoned from verified facts,
`[Unverified]` needs an experiment, and the experiment is named.

Every design decision below that carries a **⊗** closes a specific finding in
[`02-ARCHITECTURE-ATTACK.md`](02-ARCHITECTURE-ATTACK.md) or [`00-critique.md`](00-critique.md). The
finding ID is cited so the closure can be audited rather than trusted.

---

## 1. Where Trimmy sits

Three workspaces, one repository, no shared build. Trimmy depends on both others as libraries and
edits neither.

```
sdk/       flare-dart — reads Flare, builds transactions, never signs.
           Trimmy uses: ContractRegistry resolution, FtsoV2 reads, FAssets and
           Smart Accounts bindings, event log decoding, revert diagnosis.

plimsoll/  preflight and settlement verification for irreversible XRPL→Flare payments.
           Trimmy uses: arming-payment preflight (refuse to sign a losing payment),
           0xFE user-operation decoding, terminal-state classification after arming.

trimmy/    this workspace. Conditional execution for XRP.
```

The dependency direction is strict and one-way: `trimmy → plimsoll → sdk`. A need flowing the other
way is a change request against that workspace, made deliberately.

### Why Plimsoll is load-bearing here, not decorative

The arming payment is an irreversible XRPL payment carrying a 42-byte memo that commits to
`keccak256(PackedUserOperation)`. Xaman shows the user 42 opaque bytes. `[Verified]` If the batch
inside that commitment is wrong, the money is gone and there is no recourse — which is precisely the
failure class Plimsoll was built to prevent.

So Plimsoll is not an add-on. It is the only thing standing between a user and an unreadable
irreversible commitment, and it does two distinct jobs:

1. **Preflight** — dry-run every inner call of the arming batch against live chain state, and refuse
   to produce a payment that would fail or lose money.
2. **Independent decode** — `plimsoll decode <memo-hex>` renders the committed batch in plain terms.

**⊗ A1-adjacent.** Job 2 must be a *standalone, network-independent CLI with a published
`RuleParams` ABI*, because the decoder and the front end are written by the same team — so a
front-end compromise takes an in-app decoder with it. Shipping the decoder separately, and decoding
a batch we did not generate on stage, converts the weakest claim in the submission into the
strongest.

---

## 2. Toolchain, pinned and checked

Checked against upstream release feeds on **2026-08-07**, per the standing rule that versions are
verified at build time rather than recalled.

| Component | Pinned | Notes |
|---|---|---|
| Solidity | **0.8.36** | `binaries.soliditylang.org` `latestRelease` |
| Foundry | **1.7.1** | local install already current |
| forge-std | **v1.16.2** | released 2026-06-30 |
| OpenZeppelin Contracts | **v5.7.0** | GitHub latest release 2026-07-29. npm registry still serves 5.6.1, so install by git tag, not npm |
| Go (FCC extension) | **1.26.5** | not yet installed. Go is the only one of the three extension languages that is bit-for-bit reproducible across machines — Python and TypeScript embed host paths, so a rebuild changes the code hash and forces re-registration on a VM billed by the hour |
| xrpl.js | **5.0.0** | arming payment construction |
| viem | **2.55.11** | keeper and front end |

`solc 0.8.36` is used with `via_ir = true` and `optimizer_runs = 1_000_000`. The contract is deployed
once and never upgraded, so optimising for runtime gas over deploy cost is correct.

---

## 3. The execution model: allowance-pull

### 3.1 What forced it

`PersonalAccount.executeUserOp` is `onlyController`. A raw `eth_call` with selector `0x2b2ee783`
returns `0x` from the controller `0x434936d4…` and reverts `OnlyController()` (`0x59907813`) from
any other caller. The modifier is present in **both** deployed implementations. `[Verified — live
Coston2 read, GROUND-TRUTH §1]`

Therefore:

- A keeper can **never** drive a user's personal account.
- Any design that "re-arms" by submitting a fresh user operation is **impossible** without a new
  XRPL payment from the user.
- The **only** durable authorization a user can grant without being present again is an **ERC-20
  allowance**, granted inside the arming batch, which the controller executes on their behalf.

This single measurement invalidated three documents. It is also, on inspection, a better design than
the one it killed.

### 3.2 The arming batch

The XRPL payment carries memo opcode `0xFE`. The controller executes a two-call batch on the user's
personal account:

```
calls[0]  FXRP.approve(TRIMMY, exactAllowance)
calls[1]  TRIMMY.arm(RuleParams)
```

`msg.sender` for both inner calls is the **personal account**. So `arm()` binds
`rules[id].account = msg.sender`, and the allowance is granted by the personal account to the Trimmy
**contract** — never to a keeper EOA.

`exactAllowance` is sized exactly: `totalSellAmount + maxTotalKeeperFee + maxTotalProtocolFee`. Not
`type(uint256).max`, not a round number. An allowance is a standing liability and it is sized to the
rule's whole life and no more.

**⊗ Critique M2.** Before the payment is signed, the preflight asserts that the personal account it
is about to arm is (a) derived from the controller returned by `AssetManager.getSmartAccountManager()`
at runtime, and (b) holds a non-zero balance of `sellToken`. Two live controllers exist on Coston2
with identical ABIs; arming against the wrong one sets an allowance on an empty account and every
execution reverts on `transferFrom` forever, silently and unrecoverably. `[Verified — GROUND-TRUTH §2]`

### 3.3 The trust model, ranked

The claim *"maximum damage from a leaked keeper key is zero"* was proven true function by function.
It is also **the wrong headline**, because three adversaries sit strictly above the keeper. `[Verified
— 02-ARCHITECTURE-ATTACK Q2]`

| # | Adversary | Needs | Maximum extraction | Mitigation |
|---|---|---|---|---|
| 1 | **Front end / arming path** | control of the code that builds `RuleParams` | 100% of allowance | §4.2 immutable allowlists; independent Plimsoll decode; `receiver` deleted |
| 2 | **Any anonymous observer** | nothing | `slippageBips` per execution, with certainty | §5.4 tight band, arm-time depth cap, jitter |
| 3 | **Enclave operator (us)** | refusing to run | censors every FCC-gated rule | §8.4 signed on-chain heartbeat, degraded-state UI |
| 4 | **Keeper key holder** | the key | **zero** — grants no capability the public lacks | `execute()` is permissionless |

We publish this table rather than the zero. A judge cannot knock it down, and it is honest.

---

## 4. The Rule

### 4.1 One struct

`keeper-security.md` §3.3 and `rule-taxonomy.md` §3.1 shared almost no field names and were written
without reading each other. `[Verified — critique C6]` This is the merged, corrected struct.

```solidity
struct Rule {
    // identity and authorization
    address account;          // the personal account; == msg.sender at arm()
    uint32  epoch;            // ⊗ A-auth: checked in execute(); cancelAll() bumps
    uint8   sellTokenId;      // index into immutable allowlist
    uint8   buyTokenId;       // index into immutable allowlist

    // what to do
    uint8   verb;             // SWAP | DEPOSIT_VAULT | EXIT_VAULT
    uint8   venueId;          // index into immutable allowlist
    uint128 totalSellAmount;  // lifetime budget, sellToken units
    uint128 partSellAmount;   // per-execution size
    uint128 received;         // ⊗ A9: measured delta in, not claimed

    // when to do it
    uint8   trigger;          // PRICE_BELOW | PRICE_ABOVE | SCHEDULE | PRIVATE
    uint64  triggerValue;     // price in feed units, or interval seconds
    uint64  nextEligibleAt;   // schedule cursor
    uint64  expiry;

    // guards
    uint16  slippageBips;     // <= MAX_SLIPPAGE_BIPS
    uint128 minOutAbsolute;   // user floor, independent of oracle
    uint64  latchedPrice;     // ⊗ A12: 0 until first fire, then read every part
    uint64  claimableAt;      // ⊗ L5: set by execute() on EXIT_VAULT

    // fees — ⊗ C3: two fields, not one
    uint128 keeperFeeFlat;    // buyToken units; competed to gas
    uint128 keeperFeePaid;
    uint16  protocolFeeBips;  // committed at arm time, non-contestable
}
```

`sellTokenId`, `buyTokenId` and `venueId` are **indices into immutable arrays**, not addresses.

### 4.2 ⊗ A1 — the Critical fix

The attack was: `venue`, `buyToken` and `receiver` were free `address` fields with no allowlist
anywhere in validation, so a hostile front end arms
`{buyToken: EvilToken, venue: EvilVenue, receiver: attacker, minOutAbsolute: 1}` and takes 100%
while every invariant still holds — *the caller loosened nothing, the rule was already hostile*.

Three changes, each eliminating the class rather than patching the instance:

1. **`receiver` is deleted.** Proceeds always go to `rules[id].account`. There is no field to abuse
   and no code path that sends value anywhere else.
2. **Venues and tokens are immutable constructor arrays.** Not a registry — a registry with an owner
   is a rug vector, and the earlier design correctly forbade one. Immutable arrays set at
   construction on a non-upgradeable contract are fixed forever and fully auditable at deploy time.
   A rule can only name an index that already exists.
3. **Both quote legs are pinned at construction.** Each allowed token carries its FTSO `feedId` and
   its token decimals as compile-time constants. **⊗ Critique M3** — a single XRP/USD read only
   yields a correct floor if the buy token is worth exactly $1, an assumption that was never stated
   or validated, against a Coston2 landscape carrying at least five unrelated "USDC" tokens.

### 4.3 ⊗ A5 — no user-supplied route

The old design committed a `bytes32 pathHash` over a V2-style `address[] path`, and specified it as
`keccak256(abi.encode(path))` while checking `keccak256(path)` — never equal, so every rule armed to
spec would revert `WrongPath()` forever with a live allowance. `[Verified]`

The fix deletes the field. **No route is supplied by anyone.** The V3 path is derived on-chain from
the allowlisted `(sellToken, feeTier, buyToken)` triple, all three of which are immutable. There is
nothing left to mismatch.

This is also forced by the venue reality: **no Coston2 router implements `swapExactTokensForTokens`.**
All five deployed SwapRouters are Uniswap V3 — `exactInput`, `exactInputSingle`, `exactOutput`,
`exactOutputSingle`. `[Verified — GROUND-TRUTH §4d]` The V2-shaped design targeted an interface that
does not exist here.

---

## 5. `execute()` — permissionless, and every bound re-derived

### 5.1 Sequence

```
execute(ruleId, minOutHint)                       // callable by anyone

 1  load rule; require active, not expired, epoch matches
 2  require block.timestamp >= nextEligibleAt      // schedule / cooldown
 3  read FTSO for BOTH legs
      require block.timestamp - ts <= maxFeedAge   // ⊗ rule 6: in-contract age
 4  evaluate trigger against the fresh price
      PRICE_BELOW: require px <= triggerValue
      if latchedPrice == 0 { latchedPrice = px }   // ⊗ A12: latch on first fire
 5  amount = min(partSellAmount, totalSellAmount - spent)   // ⊗ A8: no dust brick
 6  balBefore = sellToken.balanceOf(this)
    sellToken.transferFrom(account, this, amount)
    received = sellToken.balanceOf(this) - balBefore        // ⊗ A9: measured delta
 7  floorOut = quote(received, latchedPrice) * (1e4 - slippageBips) / 1e4
    floorOut = max(floorOut, minOutAbsolute)                // ⊗ A12: floor off latch
 8  out = venue.exactInput(derivedPath, received, floorOut)
 9  actualOut = buyToken.balanceOf(this) - buyBalBefore     // ⊗ A15: measured, not claimed
    require(actualOut >= floorOut)
10  pay keeperFeeFlat to msg.sender; protocolFeeBips to recipient
11  transfer remainder to rule.account
12  spent += received; advance nextEligibleAt with jitter   // ⊗ A2
```

`msg.sender` appears exactly once, at step 10, as fee recipient. That is the whole of what a keeper
is trusted with. **⊗ rule 3.**

### 5.2 ⊗ A2 — the second Critical fix

The attack: `floorOut` is computed from public inputs, so it is a **publicly computable target
price**. One atomic transaction pushes the pool until it returns exactly `floorOut`, calls
`execute()`, and swaps back. Both `require`s pass at equality. Riskless profit of
`oracleOut × slippageBips / 1e4`, reached with certainty, needing no keys. `[Verified]`

This cannot be eliminated — any floor is a target — so it is **bounded** on three axes:

1. **`MAX_SLIPPAGE_BIPS = 50`**, not the 100–200 previously proposed. The extractable band is linear
   in slippage, so this is a direct 2–4× reduction in the attacker's take.
2. **Arm-time depth cap.** `partSellAmount` is capped against pool depth **once, at `arm()`** — not
   per execution. Doing it per execution would itself be an AMM read, handing an attacker a cheap
   censorship primitive: move the shallow side and block every rule in the pair. **⊗ critique C7,
   rule 4.**
3. **Jitter on `nextEligibleAt`** for every direction, so execution timing is not predictable.
   `rule-taxonomy` §5.2's `span = interval` for price rules removed the only defence and is reverted.

**Honest residual:** an attacker still takes up to 50 bips per execution. We state that number in
the submission rather than claiming it is zero.

### 5.3 ⊗ L5 — two-phase vault exit

`maxWithdraw()` and `maxRedeem()` return **0 on all three** FXRP vaults. They are request/claim
queues with `lagDuration` of 300 s and 86,400 s. `[Measured — GROUND-TRUTH §4a]` No vault-exit rule
can execute synchronously, and the obvious workaround — request now, re-arm to claim — is forbidden
by `onlyController`.

So one rule carries **two permissionless entry points**:

```
execute(ruleId)   EXIT_VAULT → vault.requestRedeem(...); rule.claimableAt = now + lag
claim(ruleId)     require now >= claimableAt; vault.claimWithdraw(...); settle and pay out
```

Both are callable by anyone. `claim()` re-derives the floor identically to `execute()`.

### 5.4 ⊗ L2 — fee starvation

On a 52-week schedule the tail executions compute `fee = cap - paid = 0`. Nothing reverts; the rule
is simply unprofitable, so no rational keeper runs it — and the user cannot self-execute, because
they have no EVM key. A silent stop with months left and a live allowance. `[Verified]`

`arm()` refuses any rule whose fee budget cannot fund its own maximum execution count:

```
require(keeperFeeFlat * maxExecutions <= keeperFeeBudget)
```

---

## 6. Quoting: the function nobody wrote

`_quote()` is where the A1 decimals attack, the missing buy-leg feed, and the SDK's hard-won
*"never assume a decimal scale"* rule all land. It is written first and fuzzed hardest.

The SDK measured one live call returning **8 dp for FLR/USD, 2 for BTC/USD, 3 for ETH/USD and 6 for
XRP/USD** — and the DA Layer reporting 6 dp for the same FLR/USD feed that FTSOv2 reports at 8 dp.
`[Verified — sdk/AGENTS.md rule 2]` FTSO decimals are `int8` and **may be negative**.

```
quote(amountIn, sellFeed, buyFeed)
  = amountIn
  × (sellValue × 10^-sellDecimals)
  ÷ (buyValue  × 10^-buyDecimals)
  × 10^(buyTokenDecimals - sellTokenDecimals)
```

Rules, all enforced:

- `value` and `decimals` travel together, always. Never one without the other.
- `int8` decimals, negative included. Every intermediate is `BigInt`-width; narrowing happens at one
  visible place.
- Multiply before divide, and prove no intermediate overflows `uint256` for the full domain.
- Both legs read fresh in the same call, both staleness-checked.

**Property test, required:** fuzz `dec ∈ [-18, 18] × tokenDecimals ∈ {6, 18}` and assert
`quote(quote(x, p), 1/p)` is within 1 unit of `x`. Differentially test against a Python reference
rather than against our own inverse, since self-consistency proves nothing.

---

## 7. Rule catalogue

The engine is one mechanism. These are configurations of it, not special cases.

| Rule | Verb | Trigger | Venue reality on Coston2 |
|---|---|---|---|
| Auto-earn | `DEPOSIT_VAULT` | `SCHEDULE` or on-arrival | **live** — TESTearnXRP, 5.9% accrued |
| Round-up savings | `DEPOSIT_VAULT` | `SCHEDULE` | live |
| Drip payout | `EXIT_VAULT` | `SCHEDULE` | live, two-phase |
| Dead-man switch | `EXIT_VAULT` | `SCHEDULE` (no heartbeat) | live, two-phase |
| Take-profit | `SWAP` | `PRICE_ABOVE` | **our own seeded pool** |
| Protective exit | `SWAP` | `PRICE_BELOW` | **our own seeded pool** |
| DCA | `SWAP` | `SCHEDULE` | our own seeded pool |
| Private trigger | any | `PRIVATE` | FCC extension, §8 |

**⊗ Critique §4 + 4b.** The demo leads with **TESTearnXRP** (share price 1.05917, a real 5.9%
accrued), **not** stXRP — whose `totalAssets() == totalSupply()` makes its share price exactly
`1.000000`, meaning it has never accrued a unit of yield and a judge falsifies "live funded vault"
with two `cast call`s. `[Measured — GROUND-TRUTH §4b]` stXRP additionally carries a hard 1,000,000
FXRP global deposit cap whose headroom anyone can fill to DoS every rule pointed at it.

---

## 8. What we say, and what we do not

Ten claims were audited for falsifiability on stage. `[Verified — 02-ARCHITECTURE-ATTACK Q5]`

**Retired — falsifiable as written:**

- ~~"Stop-loss protection"~~ → **"one-block conditional execution against the FTSO with an
  oracle-enforced floor, 1–3 seconds measured."** The keeper reads the same feed the contract
  re-checks, so it has zero information advantage: a wick shorter than one block reverts, and
  near-threshold oscillation makes reverts the common case. `[Measured — GROUND-TRUTH §5]`
- ~~"Max damage from a leaked keeper key is zero"~~ → the ranked adversary table, §3.3.
- ~~"Trimmy never holds the assets"~~ → "holds an allowance, never a balance, **except within a
  single atomic transaction**."
- ~~"One XRPL payment"~~ → true of **arming only**. A rule over FXRP presupposes FXRP, and minting
  is lot-quantised over a 0.2 XRP + 1 drop dead zone. The honest first run is two payments, and it
  goes on the first slide rather than colliding with the demo.

**Kept verbatim:**

- "The keeper is trusted with nothing" — verified function by function.
- "`execute()` re-derives every bound on-chain."
- "80 of 80 `getPool` calls returned `address(0)`, so we deployed and seeded our own pool — and we
  are telling you."

### 8.4 The two halves have different trust models

Permissionlessly-executable rules and FCC-gated rules are **not** equally trustless. A private-trigger
rule depends on a fresh signed verdict from one enclave, with a bounded result TTL and credentials in
volatile memory that a VM restart wipes. The enclave operator — us — can censor every such rule by
not running. That gets a signed on-chain heartbeat so the front end can show *degraded*, and it gets
said plainly every time.

---

## 9. Build order

1. `_quote()` + its fuzz suite — everything else depends on it being right.
2. `Trimmy.sol`: `arm`, `execute`, `claim`, `cancel`, `cancelAll`, immutable allowlists.
3. Invariant suite: `Σ paid ≤ Σ received`; no path where a caller loosens a bound; every rule either
   executable or cancellable, never neither.
4. Deploy + seed the FXRP/testUSDT V3 pool on Coston2.
5. Keeper.
6. Plimsoll arming preflight + standalone `decode` CLI.
7. Front end (Xaman payload; no install, no wallet-connect).
8. FCC private-trigger extension.

## 10. Open, and how each is settled

| # | Question | Experiment |
|---|---|---|
| O-1 | Can a V3 FXRP pool be created and seeded on Coston2? `createPool` was never attempted. | `createPool(FXRP, testUSDT, 3000)` then `mint`; measure C2FLR and FXRP needed. On the critical path for the whole swap half. |
| O-2 | `maxFeedAge` production value | Sample several separated windows; take the **max of the p99s**. One calm window's p99 refuses to execute during exactly the stalls that matter. |
| O-3 | Gas cost of `execute()`, hence minimum viable `keeperFeeFlat` | Deploy to Coston2 and measure. Sets the refuse-to-arm threshold. |
| O-4 | Does `AssetManager.redeem` accept a third-party redeemer with a user-specified XRPL destination? | Read the verified AssetManagerFXRP source; determine whether the destination is a parameter or derived from `msg.sender`. Decides whether redeem-to-XRPL rules survive allowance-pull. |
| O-5 | Do fee-only direct mints (`netMintAmountXrp: 0`) succeed or revert? | One Coston2 XRPL payment with a `0xFE` memo and zero net mint. Sits directly under the product's first sentence. |
