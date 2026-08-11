---
title: Contracts
summary: The public surface of Trimmy: the Rule struct, the enums, every entry point with its selector, the custom errors, and the test configuration.
order: 2
---

Source:
[`Trimmy.sol`](https://github.com/Immadominion/trimmy/blob/main/contracts/src/Trimmy.sol),
[`Quote.sol`](https://github.com/Immadominion/trimmy/blob/main/contracts/src/Quote.sol),
[`Interfaces.sol`](https://github.com/Immadominion/trimmy/blob/main/contracts/src/Interfaces.sol).
Built with solc 0.8.36, `via_ir`, `optimizer_runs = 1_000_000`, `evm_version = cancun`.

## Deployment

Read from the live contract on 2026-08-11. Coston2 only.

| | |
| --- | --- |
| `Trimmy` | `0x19F81AAB43f7a26B0659754b70179aDcAF43ef7C` |
| `TrimmyConfidentialTrigger` | `0x02EA709e2278EACDbA00D4A88caA604E3b35293b` |
| `REGISTRY` (the only literal) | `0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019` |
| `tokenAt(0)` | FXRP `0x0b6A3645c240605887a5532109323A3E12273dc7`, feed `XRP/USD`, 6 dp |
| `tokenAt(1)` | WC2FLR `0xC67DCE33D7A8efA5FfEB961899C73fe01bCe9273`, feed `FLR/USD`, 18 dp |
| `venueAt(0)` | SwapRouter `0xe2B3aE21461c4ad3415210630EA210e9F53CCEBc`, `SWAP_ROUTER_V3`, fee tier 3000 |
| `venueAt(1)` | TESTearnXRP `0x9E63a5D282F2fBb7DcE822B98e363b2719D28319`, `QUEUED_VAULT` |
| `maxFeedAge()` | 64 |
| `protocolFeeRecipient()` | `0x38d58d1BEA8FF21fd8397494f17F64A99bcF8E83` |

Constants: `MAX_SLIPPAGE_BIPS` 50, `MAX_PROTOCOL_FEE_BIPS` 50, `MIN_SCHEDULE_INTERVAL` 60,
`LATCH_DECAY_WINDOW` 1 hour, `MAX_RULE_LIFETIME` 365 days.

## Enums

`Verb`: `SWAP` 0, `DEPOSIT_VAULT` 1, `EXIT_VAULT` 2.
`Trigger`: `PRICE_BELOW` 0, `PRICE_ABOVE` 1, `SCHEDULE` 2, `PRIVATE` 3.
`VenueKind`: `SWAP_ROUTER_V3` 0, `QUEUED_VAULT` 1.

## Rule

Packed into eight slots. Field order is load-bearing for that packing.

```solidity
address account;          // the personal account; == msg.sender at arm()
uint32  epoch;            // must equal epochOf[account] or the rule is dead
uint8   sellTokenId;      // index into the immutable token allowlist
uint8   buyTokenId;
Verb    verb;
uint8   venueId;          // index into the immutable venue allowlist
Trigger trigger;
bool    active;
uint128 totalSellAmount;  // lifetime budget, sell-token base units
uint128 partSellAmount;   // per-execution size
uint128 spent;            // measured deltas in, not amounts requested
uint128 minOutAbsolute;   // user floor, independent of the oracle
uint128 triggerValue;     // relative price, or interval seconds for SCHEDULE
uint128 latchedPrice;     // 0 until first fire, then decays back to live
uint64  nextEligibleAt;
uint64  expiry;
uint64  claimableAt;      // EXIT_VAULT
uint64  claimPeriod;      // EXIT_VAULT: the vault's day-index bucket
uint128 keeperFeeFlat;    // buy-token units, per execution
uint128 keeperFeeBudget;  // lifetime cap
uint128 keeperFeePaid;
uint128 pendingShares;    // EXIT_VAULT: queued, awaiting claim
uint16  slippageBips;
uint16  protocolFeeBips;
uint128 pendingAssets;    // EXIT_VAULT: assets owed for pendingShares
uint64  latchedAt;        // when latchedPrice was set
```

`triggerValue` and `latchedPrice` are relative prices: buy-token base units per one whole sell token.
For FXRP to WC2FLR the exponent is `(18 + 8) - (6 + 6) = +14`, so the value is around 1.7e20, which
is 9.3x past `uint64`. They were `uint64` in an earlier build and the latch saturated; a rule armed
at 50 bips of slippage settled at roughly 10.7% of oracle fair value while reporting that it had
honoured its floor.

`RuleParams` is deliberately not the storage struct. A caller supplies intent only:
`sellTokenId, buyTokenId, verb, venueId, trigger, totalSellAmount, partSellAmount, minOutAbsolute,
triggerValue, expiry, slippageBips, protocolFeeBips, keeperFeeFlat, keeperFeeBudget`. Everything
else is derived.

## Entry points

Every selector below was computed with `cast sig` and confirmed present in the deployed runtime at
`0x19F81AAB...`.

| function | selector | who may call |
| --- | --- | --- |
| `arm((uint8,uint8,uint8,uint8,uint8,uint128,uint128,uint128,uint128,uint64,uint16,uint16,uint128,uint128))` | `0xcc0c55f4` | anyone; binds `msg.sender` as `rule.account` |
| `execute(uint256)` payable | `0xfe0d94c1` | anyone |
| `claim(uint256)` | `0x379607f5` | anyone |
| `cancel(uint256)` | `0x40e58ee5` | `rule.account` or its guardian |
| `cancelAll(address)` | `0x97e8f717` | that account or its guardian |
| `setGuardian(address)` | `0x8a0dac4a` | the account itself |
| `currentPrice(uint256)` payable | `0x7a3c4c17` | anyone; not a view, `getFeedById` is payable |
| `ruleAt(uint256)` | `0x63a6fef6` | view; reverts `NoRule` past the end |
| `ruleCount()` | `0xf6bcf633` | view; rule ids are array indices |
| `tokenAt(uint8)` | `0xbc13f2a4` | view; reverts `UnknownToken` |
| `venueAt(uint8)` | `0x5ad2dfd6` | view; reverts `UnknownVenue` |

Remaining views: `tokenCount()` `0x9f181b5e`, `venueCount()` `0x8d640d4b`, `ftsoV2()` `0x25e89883`,
`epochOf(address)` `0x582805d9`, `guardianOf(address)` `0xacd52e8d`,
`confidentialTrigger()` `0xbcb7f3ca`.

`arm()` was `0xc33d4cc3` before `triggerValue` widened to `uint128`. Widening the field changed the
selector, so an off-chain encoder pinned to the old one silently builds calldata nothing answers.

`arm()` refuses, rather than accepts and warns: unknown token or venue id, zero or oversized part,
slippage above 50 bips, protocol fee above 50 bips, an expiry in the past or beyond 365 days, a
`SCHEDULE` interval under 60 seconds, a non-zero `triggerValue` on a `PRIVATE` rule, a zero
`triggerValue` on a price rule, a venue whose kind does not match the verb, a vault whose `asset()`
does not match the sell token (or, for `EXIT_VAULT`, a sell token that is not the share token), and
a fee budget that cannot fund `ceil(total / part)` executions (doubled for `EXIT_VAULT`, which pays
per `execute` and again per `claim`).

`execute()` loads the rule, checks active, expiry, epoch, eligibility and exhaustion, reads both FTSO
legs fresh and age-checks them, evaluates the trigger, latches the first price it fires at, pulls the
measured delta with `safeTransferFrom`, derives the floor from the decayed latch rather than from any
venue quote, calls the venue, measures what actually arrived, and pays. `PRIVATE` rules call
`confidentialTrigger.consumeVerdict(ruleId, spent)`, with `spent` as the nonce so one verdict covers
one part.

`claim()` completes a queued vault exit. It deliberately bypasses the liveness checks: the shares are
already burned, so a cancelled or stale-epoch rule must still be able to collect, and in that case
fees are zeroed.

## Errors

Deploy: `EmptyAllowlist`, `ZeroAddress`, `TokenDecimalsMismatch(address,uint8,uint8)`.
Arming: `UnknownToken(uint8)`, `UnknownVenue(uint8)`, `VenueKindMismatch(uint8,Verb)`,
`VaultAssetMismatch(address,address,address)`, `SameToken`, `ZeroAmount`, `PartExceedsTotal`,
`SlippageTooHigh(uint16,uint16)`, `ProtocolFeeTooHigh(uint16,uint16)`, `BadExpiry`,
`ScheduleTooFast(uint64,uint64)`, `FeeBudgetCannotFundExecutions(uint128,uint256)`,
`PrivateRuleMustNotPublishThreshold`.
Execution: `NoRule(uint256)`, `RuleInactive(uint256)`, `RuleExpired(uint256)`,
`StaleEpoch(uint32,uint32)`, `NotYetEligible(uint64)`, `TriggerNotMet(uint256,uint128)`,
`Exhausted`, `FloorBreached(uint256,uint256)`, `InsufficientFeeValue(uint256,uint256)`,
`PrivateTriggersDisabled`.
Vault exit and authority: `RedemptionAlreadyPending(uint64)`, `NotYetClaimable(uint64)`,
`NothingPending`, `WrongVerb`, `NotAuthorised`.
From `Quote`: `FeedValueZero`, `ExponentOutOfRange(uint256)`, `FeedStale(uint64,uint256,uint64)`,
`FeedFromTheFuture(uint64,uint256)`. A feed more than `MAX_CLOCK_SKEW` (10 s) ahead of
`block.timestamp` is refused, because the latch would carry a poisoned price for the rule's life.

## Tests

`forge test --no-match-path "test/research/*"` runs 92 tests:

| suite | tests |
| --- | ---: |
| `Trimmy.t.sol` | 25 |
| `Quote.t.sol` | 15 |
| `ConfidentialTrigger.t.sol` | 11 |
| `VerdictBinding.t.sol` | 8 |
| `M1Verify.t.sol` | 7 |
| `PrivateTrigger.t.sol` | 7 |
| `TrimmyInvariant.t.sol` | 7 |
| `LatchRegression.t.sol` | 5 |
| `M3Regression.t.sol` | 4 |
| `TrimmyCoverage.t.sol` | 2 |
| `QuoteDifferential.t.sol` | 1 |

Fuzz: `runs = 10_000`, `max_test_rejects = 500_000`. Invariant: `runs = 512`, `depth = 64`,
`fail_on_revert = false`, with one handler as the sole `targetContract`. The `deep` profile raises
these to 500,000 fuzz runs and 4,096 invariant runs at depth 256. The seven invariants: Trimmy
retains neither sell nor buy token, proceeds are fully accounted as user plus keeper plus protocol,
`spent` never exceeds the budget, `keeperFeePaid` never exceeds `keeperFeeBudget`, an exhausted rule
is never left active, and an executed rule always has a latched price. Handler reach into `execute`
is proven separately in `TrimmyCoverage.t.sol` rather than in `afterInvariant`, because a coverage
assertion is not shrink-stable. The adversarial suites under `test/research/` are excluded from that
count and from the `deny = "warnings"` gate; they are evidence, not production code.

## Limits

This deployment is on Coston2 testnet. Nothing has run on Flare mainnet, so no figure here is a
mainnet figure. `venueAt(0)` routes into an FXRP/WC2FLR pool we deployed and seeded ourselves, and
it is thin. `PRIVATE` rules depend on `TrimmyConfidentialTrigger` and on one enclave staying up,
so the enclave operator can censor them by declining to act; the other three triggers are
permissionless and re-derive every bound on chain. The contract has no owner, no pause and no
rescue, so a wrong constructor argument cannot be corrected, only abandoned.
