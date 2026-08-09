# Keeper security — prior art and a threat model for Trimmy

**Date:** 2026-08-06 · **Author:** keeper-security research pass · **Status:** design input, adversarial

Evidence labels follow the repo convention: `[Verified]` primary source / live chain / code actually
read · `[Measured]` computed from an identified experiment or corpus that is cited · `[Inference]`
reasoned from stated verified facts · `[Unverified]` still needs an experiment, and the experiment is
named.

Every live read in this document used `https://coston2-api.flare.network/ext/C/rpc` (chain ID 114) on
**2026-08-06** and is reproducible with the command shown.

---

## 0. The one-sentence finding

> **Trimmy's keeper must have no privileges at all.** Every measured constraint in the Flare Smart
> Accounts stack points the same way: the personal account cannot be driven by a keeper, the only
> durable authorization an XRPL user can leave behind is an ERC-20 allowance, and the trigger
> (FTSOv2) is on-chain-readable. That combination makes **permissionless execution** not merely the
> safest design but the *natural* one — and it collapses four of the seven threat classes in the
> brief at once.

The corollary is the thing that decides whether Trimmy is trustworthy or a rug: **the maximum damage
from a total compromise of Trimmy's off-chain infrastructure must be zero**, and the maximum damage
from a total compromise of Trimmy's *contract* must be `Σ min(allowance_i, balance_i)` — a number the
user chose, that is visible on-chain, and that is never `type(uint256).max`.

---

## 1. What Flare actually permits — four measured constraints that fix the design

These were measured before any design was written, because each of them eliminates a design that
would otherwise look reasonable.

### C1 — `executeUserOp` is `onlyController`. A keeper can never drive the personal account.

`[Verified]` Read from the **verified source of the deployed** `PersonalAccount` implementation at
`0xe900cf0C3f1320816700c669B002835aCc9A93A6` (resolved via `implementation()`):

```solidity
contract PersonalAccount is
    IIPersonalAccount, ReentrancyGuardTransient,
    ERC721Holder, ERC1155Holder, IERC1363Receiver
{
    address public controllerAddress;
    string  public xrplOwner;

    modifier onlyController() {
        require(msg.sender == controllerAddress, OnlyController());
        _;
    }

    function executeUserOp(IPersonalAccount.Call[] calldata _calls)
        external payable
        onlyController nonReentrant
    {
        for (uint256 i = 0; i < _calls.length; i++) {
            (bool success, bytes memory result) = _calls[i].target.call{
                value: _calls[i].value
            }(_calls[i].data);
            if (!success) {
                revert CallFailed(i, result);
            }
        }
    }
}
```

`[Measured]` Confirmed against the live chain rather than only against source:

```bash
PA=0xa52930f85fe71ce586932cfe682e4437a93e66de
cast call $PA "executeUserOp((address,uint256,bytes)[])" "[]" \
  --from 0x1111111111111111111111111111111111111111 --rpc-url $RPC
# execution reverted, data: "0x59907813"      == OnlyController()   (cast sig "OnlyController()")

cast call $PA "executeUserOp((address,uint256,bytes)[])" "[]" \
  --from 0x434936d47503353f06750db1a444dbdc5f0ad37c --rpc-url $RPC
# 0x                                            == success, from the MasterAccountController
```

**Consequence.** There is no session key, no delegate, no module system. The *only* path into the
personal account is `MasterAccountController → executeUserOp`, and the only path into the controller
is an FDC-attested XRPL payment. A Trimmy keeper holding any key whatsoever cannot make the personal
account do anything. This is a much stronger starting position than Gelato's or Chainlink's, where
the automation network is granted a callable entry point on the user's contract.

### C2 — the arming batch is unrestricted and atomic

`[Verified]` `executeUserOp` is a raw `.call{value}` loop with **no target allowlist, no selector
filter, no value cap**, and it reverts the entire batch on the first failure with
`CallFailed(uint256,bytes)` (selector `0x5c0dee5d`, `[Measured]` via `cast sig`). Note this is a
*different* selector from the controller's `CallFailed(bytes)` — a decoder must carry both
(GROUND-TRUTH §5.3).

**Consequence, good:** one arming payment can atomically do
`[FXRP.approve(Trimmy, cap), Trimmy.arm(params)]`. If `arm` reverts, the approval rolls back. There is
no window in which an allowance exists without a rule governing it.

**Consequence, bad:** the arming batch is also the *most dangerous* object in the system. A malicious
or buggy front end can put `FXRP.approve(attacker, MAX)` in that batch and the user, signing an XRPL
payment in Xaman, sees only a 42-byte memo. **This is precisely and entirely what Plimsoll exists to
catch** — see §7.T6.

### C3 — `msg.sender` inside the batch is the personal account. Trimmy gets Autonomy's `verifyUser` for free.

`[Inference — from C1's source, which performs a genuine `CALL` from the personal account]` Because
`executeUserOp` uses `.call` and not `delegatecall`, every inner call arrives at its target with
`msg.sender == address(personalAccount)`. The personal account address is a deterministic CREATE2
function of the XRPL address (`getPersonalAccount(string)` on facet
`0xa071b43060DaA8eaA0d14DBE5Ea03ed18c9ed1d6`, GROUND-TRUTH §5).

This is worth stating loudly because **Autonomy Network had to build a whole contract to get this
property** (§2.1). Trimmy gets it from the platform. `Trimmy.arm()` binds a rule to `msg.sender` and
that is a complete, unforgeable statement of "which XRPL user armed this".

### C4 — reentrancy is deliberately re-enabled around `handleMintedFAssets`

`[Verified]` Read from the verified source of the deployed `DirectMintingFacet`
(`0x4aFaEda2AC4442cD10Ac601622Eee0dF5DF78eeF`), `_mintToSmartAccounts`:

```solidity
uint256 mintedAmountUBA = _receivedAmountUBA - _mintingFeeUBA;
_mintFAssets(address(state.smartAccountManager), mintedAmountUBA);
// Smart accounts may trigger operations on asset manager (e.g. redeem) when they get instructions
// via handleMintedFAssets. For this to work, reentrancy has to be allowed from this point on.
// This is safe, because `handleMintedFAssets` is the last operation
// in executeDirectMinting/executeDirectMintingWithData.
Reentrancy.nonReentrantAfter();
// notify smart account manager
state.smartAccountManager.handleMintedFAssets{ value: msg.value }(...);
```

`[Verified]` And the library it calls (`flare-foundation/fassets@main`,
`contracts/openzeppelin/library/Reentrancy.sol`) confirms `nonReentrantAfter()` simply writes
`status = _NOT_ENTERED` into diamond storage at slot
`keccak256("utils.ReentrancyGuard.ReentrancyGuardState")`. It is a *clear*, not a restore — there is
no saved previous value.

**Three consequences for Trimmy, and they are not the obvious one:**

1. **The AssetManager's guard is genuinely open during the arming batch.** Any Trimmy code running
   inside the arming batch executes in a context where `AssetManager` can be re-entered. Flare's
   safety argument is positional ("it is the last operation"), not structural — it holds only as long
   as no *later* operation is added to `executeDirectMintingWithData`. Trimmy must not rely on it.
2. **The personal account is still guarded.** `PersonalAccount` is `ReentrancyGuardTransient` and
   `executeUserOp` is `nonReentrant`, so a malicious token encountered inside the batch **cannot**
   induce a second `executeUserOp`. `[Verified — source, C1]`
3. **`Trimmy.arm()` must therefore make zero external calls.** It is pure storage writes plus reads
   of its own parameters. If `arm()` never calls out, the open AssetManager guard is unreachable from
   Trimmy's code and consequence (1) becomes moot. This is a free mitigation and should be a stated
   invariant, not an accident.

### C5 — supporting facts, all live-read 2026-08-06

| Fact | Value | How |
|---|---|---|
| FXRP (Coston2) | `0x0b6A…3dc7`, name `FXRP`, symbol `FTestXRP`, **6 decimals** | `cast call … "decimals()(uint8)"` |
| FXRP EIP-2612 | `DOMAIN_SEPARATOR()` returns `0xc6a6f2e3…44ab` — **permit exists** | `cast call` |
| FXRP EIP-3009 | `authorizationState(address,bytes32)` **reverts** — no `transferWithAuthorization` | `cast call` |
| FtsoV2 | `0xC4e9c78EA53db782E28f28Fdf80BaF59336B304d` via registry `getContractAddressByName("FtsoV2")` | `cast call` |
| `getFeedById(bytes21)` | returns `(uint256 _value, int8 _decimals, uint64 _timestamp)`, **payable** | SDK binding, artifacts `0.1.52`; confirmed live |
| `calculateFeeById(XRP/USD)` | **0** | `cast call` |
| XRP/USD live | `1049423`, decimals `6` → **$1.049423** | `cast call` |
| Personal account nonce model | `getNonce(PA)` = 203, one instruction one increment | `cast call`; GROUND-TRUTH §6.2 |
| Executor pin | `getExecutor(PA)` = `0x0` (unpinned) | `cast call` |
| Coston2 block time | **1.87 s** | GROUND-TRUTH §7.1 |
| Coston2 base fee / priority | 500 gwei / 150 gwei suggested | `cast base-fee`, `eth_maxPriorityFeePerGas` |
| XRPL→FXRP settlement | p50 **131 s**, p95 **170 s** (30/30 minted) | GROUND-TRUTH §18 |

**The EIP-3009 absence matters.** It means there is no signature-based pull. The *only* durable
authorization primitive is a plain ERC-20 allowance set by the personal account. EIP-2612 `permit`
does not help either, because the personal account is a contract and cannot produce an ECDSA
signature (it would need ERC-1271, and `permit` uses `ecrecover`).

---

## 2. Prior art, studied at the contract level

I read source where source exists. Where I relied on documentation I say so, because the difference
between "the docs say" and "the deployed bytecode does" has already cost this repository real money
(GROUND-TRUTH §8.1: the docs are wrong about three of six memo opcode lengths).

### 2.1 Autonomy Network — the closest precedent, and the most instructive

`[Verified — source read]`
`Autonomy-Network/uniV2-limits-stops@master:contracts/UniV2LimitsStops.sol`, 614 lines, fetched and
read in full.

Autonomy built exactly Trimmy's product — limit orders, stop-losses and recurring payments over
PancakeSwap/Uniswap-V2 on BSC — in 2022. Four design decisions in that file are directly transferable
and one is a warning.

**(a) The trigger is not an oracle. It is the swap's own output.**

```solidity
function ethToTokenRange(
    uint maxGasPrice, IUniswapV2Router02 uni,
    uint amountOutMin, uint amountOutMax,
    address[] calldata path, address to, uint deadline
) external payable gasPriceCheck(maxGasPrice) {
    uint[] memory amounts = uni.swapExactETHForTokens{value: msg.value}(amountOutMin, path, to, deadline);
    require(amounts[amounts.length-1] <= amountOutMax, "LimitsStops: price too high");
}
```

`amountOutMin` is the router's own slippage floor (the *limit* price); `amountOutMax` is checked
afterwards (the *stop* price). A limit order sets `amountOutMax = type(uint).max`; a stop-loss sets
`amountOutMin = 0`.

This is elegant and it is also **the free-option bug in its purest form** — see §2.7. Autonomy knew,
and said so in the doc comment: *"The min/max can also be used to limit downside during flash crashes,
e.g. `amountOutMin` could be set to 10% lower than `amountOutMax` for a stop loss, if desired."* The
mitigation exists but is **opt-in and defaulted off**. Trimmy must invert that default.

**(b) The `userVeriForwarder` pattern — proving which user asked.**

```solidity
modifier userVerified() {
    require(msg.sender == userVeriForwarder, "LimitsStops: not userForw");
    _;
}
modifier userFeeVerified() {
    require(msg.sender == userFeeVeriForwarder, "LimitsStops: not userFeeForw");
    _;
}
```

`[Verified — Autonomy docs, `llms-full.txt`]` The Registry routes calls with `verifyUser=true` through
a dedicated `Forwarder`, and the docs state the guarantee precisely: *"if a contract receives a call
with msg.sender that is that Forwarder, it's guaranteed that the 1st input to the function is the
original user who made the Request."* The target contract can then `transferFrom(user, ...)` safely.

Trimmy needs none of this (C3). Note the shape though: **two** forwarders, because a call that also
charges a fee has a different trust surface from one that does not. That distinction — "the caller may
move funds" vs "the caller may also take a cut" — is worth keeping.

**(c) The fee is taken from the input, and the slippage bound is rescaled so the user's price
guarantee survives.**

```solidity
uint[] memory amounts = uni.swapExactETHForTokens{value: tradeInput}(
    uniArgs.amountOutMin * tradeInput / msg.value,   // <- rescaled
    ...
);
```

The source comment `*1` explains it: the naive approach (swap everything, then sell some output to
pay the fee) executes at the right price but costs more gas; instead they pay the fee out of the input
and scale `amountOutMin` by `tradeInput / msg.value` so **the execution price the user gets is exactly
the one they asked for, even though they receive proportionally less**. This is a genuinely good idea
and Trimmy should copy it: *a fee must never be allowed to eat into a slippage bound.*

**(d) `maxGasPrice` — a griefing bound.**

```solidity
modifier gasPriceCheck(uint maxGasPrice) {
    require(tx.gasprice <= maxGasPrice, "LimitsStops: gasPrice too high");
    _;
}
```

Autonomy reimburses the executor's gas (`fee = gas cost + 30%` in ETH, or `+10%` in AUTO
`[Verified — docs]`), so without this bound an executor could execute at 5,000 gwei and bill the user.
**Trimmy should not need this modifier, because Trimmy should not reimburse gas** — see §5, invariant
I-7. Charging a fixed fee and letting the keeper bear its own gas deletes the entire vector.

**(e) The executor model, and the part not to copy.**

`[Verified — Autonomy docs]` Executors stake AUTO in a `StakeManager`; a single executor wins
**exclusive** execution rights for a 100-block epoch, chosen from stake-weighted entries using the
blockhash before the epoch. The docs' liveness argument is economic: *"the next epoch's executor has
economic incentive to execute all pending requests for maximum profit."*

Their censorship argument is a shrug — *"if the ability for an entity to censor a Request is of
concern to someone, then they shouldn't use a blockchain in the first place"* — which conflates
"a proposer can reorder" with "one designated party has a monopoly for 100 blocks". Those are not the
same risk. **Exclusive-window execution is the single design choice from Autonomy that Trimmy should
reject.** It is also, notably, the same shape as FAssets' own
`getDirectMintingOthersCanExecuteAfterSeconds = 7200` `[Measured — GROUND-TRUTH §1]`, and
GROUND-TRUTH §10.2 already records what that costs: pinning an executor that then does nothing
strands a payment for two hours.

**(f) What Autonomy got right that everyone repeats.** The condition is a `require` in the target
contract, so *"each Request will therefore always revert if the condition is not met"* and bots simply
simulate every request after every block. The keeper never *decides* anything; it only *tries*. That
is the correct division of responsibility and Trimmy keeps it.

### 2.2 Gelato — `dedicatedMsgSender`

`[Verified — docs.gelato.cloud/web3-functions/security-considerations/dedicated-msg-sender]` Gelato
deploys a proxy per task creator and the recommended pattern is:

```solidity
require(msg.sender == dedicatedMsgSender, "Only dedicated msg.sender");
```

exposed as `onlyDedicatedMsgSender` via the `AutomateReady` base. The docs carry one warning worth
repeating: *"msg.sender restrictions should be added to the function that Gelato will call during
execution, not the checker function."*

This is the **opposite** of what Trimmy should do, and the contrast is the point. Gelato's model is
*restrict who may call, then trust them*. It is the right model when the call is a privileged
protocol operation (rebalance a vault, poke an oracle) that has no natural on-chain precondition. It
is the wrong model when the precondition is on-chain-checkable, because it converts an economic
guarantee into a trust assumption for no gain. Trimmy's precondition (an FTSO price) is
on-chain-checkable. So Trimmy restricts *what* may be done, not *who* may do it.

### 2.3 Chainlink Automation — revalidate, and do not trust `performData`

`[Verified — docs.chain.link/chainlink-automation/concepts/best-practice]` The two load-bearing
sentences:

- *"If your upkeep performs **sensitive** functions in your protocol, consider using the `Forwarder`
  to lock it down so `performUpkeep` can only be called by the `Forwarder`."*
- *"If your upkeep is on Automation v1, we recommend that you revalidate the conditions specified in
  `checkUpkeep` in your `performUpkeep` function."*
- *"ensure that `checkUpkeep` remains true until execution"* — flicker avoidance.

`[Verified — secondary, surfing-solodit.com audit writeup]` The audit community's framing is blunter:
*"Overlooking access controls on the `checkUpkeep()` and `performUpkeep()` functions … is very likely
to provide would-be attackers with one or more levers for manipulation."*

**The transferable rule is the second bullet, and it is non-negotiable for Trimmy:** whatever the
off-chain watcher believed, `execute()` re-derives the trigger from chain state and reverts if it does
not hold. `checkUpkeep`-equivalent output (Trimmy's keeper's opinion) is a *hint*, never an input to
authorization. The flicker warning is also directly the oscillation threat (§7.T7) and Trimmy's answer
to it — the latch — is stronger than Chainlink's advice.

### 2.4 1inch Limit Order Protocol v4 — bounds encoded in bits

`[Verified — `1inch/limit-order-protocol@master:description.md`, read via fetch]` The relevant
mechanisms:

| Mechanism | What it does | Transferable to Trimmy? |
|---|---|---|
| `MakerTraits[0..79]` `ALLOWED_SENDER` | last 10 bytes of the only address allowed to fill; zero = anyone | Conceptually yes — but Trimmy should deliberately leave it "anyone" |
| `MakerTraits[80..119]` `EXPIRATION` | 40-bit unix deadline; zero = never expires | **Yes, and Trimmy must forbid the zero case** |
| `TakerTraits[0..184]` `THRESHOLD` | the taker's own slippage bound, checked on-chain | Yes — the executor states a bound and it is enforced |
| Predicates: `eq`/`lt`/`gt`/`and`/`or`/`not`/`arbitraryStaticCall` | composable on-chain conditions, `staticcall` only so they cannot mutate state | Yes in spirit; **no** in generality (§5.3) |
| BitInvalidator vs RemainingInvalidator | cancellation by nonce for single-fill orders, by order hash for partially-fillable ones | Yes — Trimmy needs an explicit per-rule cancel |
| Epoch manager (`increaseEpoch`, `advanceEpoch`, `SERIES`) | mass-cancel every order in a series with one transaction | **Yes, and it is important** — see §5.4, because Trimmy's cancels are expensive |

Two observations that shaped the design below.

First, 1inch's `arbitraryStaticCall` is *`staticcall`*, explicitly: *"Calls third-party contract via
`staticcall`, returns uint256; reverts on state changes."* When a protocol lets a user express an
arbitrary condition, it constrains that condition to be side-effect-free. That is the correct
generalisation and it is exactly what a v2 Trimmy predicate system should look like.

Second, the *price* in a 1inch order is fixed at signing time. That is the free-option problem, and
1inch's only mitigations are `EXPIRATION` and the maker's ability to cancel. Trimmy can do
structurally better (§2.7).

### 2.5 CoW Protocol / ComposableCoW — the best-shaped precedent

`[Verified — docs.cow.fi ComposableCoW reference, plus source read of
`cowprotocol/composable-cow@main:src/types/twap/TWAP.sol` and `.../libraries/TWAPOrder.sol`]`

The framework splits a conditional order into two interfaces:

```solidity
// self-expressing: derive the concrete order that is currently valid
function getTradeableOrder(address owner, address sender, bytes32 ctx,
                           bytes calldata staticInput, bytes calldata offchainInput)
    external view returns (GPv2Order.Data memory);

// self-validating: revert OrderNotValid(string) if a proposed order is not authorised
function verify(address owner, address sender, bytes32 _hash, bytes32 domainSeparator,
                bytes32 ctx, bytes calldata staticInput, bytes calldata offchainInput,
                GPv2Order.Data calldata order) external view;
```

with authorization stored either as `mapping(address => mapping(bytes32 => bool)) singleOrders` or, for
batches, `mapping(address => bytes32) roots` (a merkle root — O(1) gas for n orders). Cancellation is
`remove(bytes32 singleOrderHash)`, callable by the owner.

**The TWAP order is the single best model for Trimmy's rule struct.** Read from source:

```solidity
struct Data {
    IERC20 sellToken;
    IERC20 buyToken;
    address receiver;
    uint256 partSellAmount;  // amount of sellToken to sell in each part
    uint256 minPartLimit;    // max price to pay for a unit of buyToken denominated in sellToken
    uint256 t0;              // start
    uint256 n;               // number of parts
    uint256 t;               // time between parts
    uint256 span;            // execution window within each part's interval
    bytes32 appData;
}

function validate(Data memory self) internal pure {
    if (!(self.sellToken != self.buyToken))  revert OrderNotValid(INVALID_SAME_TOKEN);
    if (!(address(self.sellToken) != address(0) && address(self.buyToken) != address(0)))
                                             revert OrderNotValid(INVALID_TOKEN);
    if (!(self.partSellAmount > 0))          revert OrderNotValid(INVALID_PART_SELL_AMOUNT);
    if (!(self.minPartLimit > 0))            revert OrderNotValid(INVALID_MIN_PART_LIMIT);
    if (!(self.t0 < type(uint32).max))       revert OrderNotValid(INVALID_START_TIME);
    if (!(self.n > 1 && self.n <= type(uint32).max)) revert OrderNotValid(INVALID_NUM_PARTS);
    if (!(self.t > 0 && self.t <= 365 days)) revert OrderNotValid(INVALID_FREQUENCY);
    if (!(self.span <= self.t))              revert OrderNotValid(INVALID_SPAN);
}
```

Six properties of this struct are exactly the mitigations the brief asks for, and they are worth
naming individually:

1. **`partSellAmount` is max notional per execution.** Bounded by construction.
2. **`minPartLimit > 0` is enforced, not optional.** Compare Autonomy, where `amountOutMin = 0` is the
   documented way to build a stop-loss. CoW makes a zero floor *impossible*.
3. **`receiver` is in the signed struct.** Destination whitelisting for free; the settler cannot
   redirect.
4. **`t0`, `n`, `t` make "which part is live" a pure function of `block.timestamp`.** The keeper does
   not choose when; it only chooses whether to bother.
5. **`span` bounds *when within each interval* execution is legal**, with `span <= t` enforced. A
   griefer cannot execute an interval's part at an arbitrary moment of its choosing across the whole
   interval — only inside the window the user opened. This is the cleanest anti-griefing primitive in
   any of the prior art.
6. **Replay protection falls out of `validTo`.** From the source comment:
   *"As `validTo` is unique, there is a corresponding unique `orderUid` for each `GPv2Order`. As
   CoWProtocol enforces that each `orderUid` is only used once, this means that each part of the TWAP
   order can only be executed once."*

`[Verified — ComposableCoW docs]` Two further ComposableCoW features Trimmy should mirror in spirit:

- **`swapGuards`** — `mapping(address => ISwapGuard)`, an owner-wide restriction layer applied
  *before* `verify()`, whose documented purpose is *"receiver locks or token whitelists"*. It runs
  first and failure is `SwapGuardRestricted()`.
- **`ConditionalOrderParams.salt`** and the requirement that *"H(ConditionalOrderParams) **MUST** be
  unique"*. Trimmy rule IDs need a salt for the same reason.

And one explicit warning that generalises: *"Order implementations **MUST** validate / verify
`offchainInput`!"* — i.e. anything the executor supplies is adversarial input. ComposableCoW also
warns that *"ComposableCoW will **NOT** verify the proof data passed in"* to `setRoot`, which is a
reminder that a framework's guarantees stop precisely where its documentation says they do.

Finally, CoW's structural MEV answer is the **batch auction with a uniform clearing price**, settled
by competing solvers. Trimmy has no equivalent venue on Flare and should not pretend otherwise
(§7.T3).

### 2.6 DCA products

**Balmy (formerly Mean Finance)** `[Unverified — I did not read `Balmy-protocol/dca-v2-core` source in
this pass]`. The repository exists and is the canonical reference for a swap-per-interval DCA
architecture with a permissionless swapper. **Experiment that would settle it:** clone
`Balmy-protocol/dca-v2-core`, read `DCAHub.sol`'s `swap()` and its `IDCAHubSwapCallee` callback, and
determine whether the caller supplies the swap route and how the minimum output is derived. I flag
this rather than paraphrase second-hand summaries.

**Jupiter DCA** `[Verified — betastation.jup.ag/guides/dca/how-dca-work]` uses two mitigations Trimmy
can adopt at zero cost:

- *"Orders are filled within a randomized padding of +/- 30 seconds from your DCA creation time to
  minimize the predictability of your DCA strategy."* — deliberate schedule jitter.
- Orders are held off-chain and private by default, *"closing the most common MEV attack vector of
  visible pending orders."*

The first is directly applicable and is the correct interpretation of CoW's `span`: **`span` is not
just a griefing bound, it is a jitter budget.** If a rule's execution may happen anywhere in a
600-second window, a searcher cannot pre-position for it at a known block. The cost is latency; for a
DCA rule that cost is zero, for a stop-loss it is not (§5.5).

The second is *not* applicable and Trimmy must say so: Trimmy's rules are on-chain by necessity
(that is what makes them permissionlessly executable), so **every armed Trimmy rule is public,
including its trigger price.** That is a real, permanent information leak and it belongs in the threat
model as T8.

### 2.7 The stop-loss free-option problem, stated properly

This is the question the brief singles out — *how do DEX-native stop-losses avoid being a free option
for the keeper?* — and it deserves a precise answer because most of the prior art does not actually
solve it.

**The problem.** A resting conditional order is a written option. Whoever may fill it holds the right,
not the obligation, to trade at the order's terms. They will exercise exactly when it is profitable
for them, which is exactly when it is unprofitable for the user. The option's value to the filler is
the gap between the order's terms and the true market price at the moment of filling.

**How each system handles it:**

| System | Mechanism | Residual free option |
|---|---|---|
| 1inch LOP | Maker fixes the price; `EXPIRATION`; maker may cancel | **Full.** The order's price is stale by construction. This is why professional makers cancel and re-post constantly. |
| CoW TWAP | `minPartLimit` fixed at signing; solvers compete in a batch auction and surplus goes to the user | **Bounded by solver competition**, not by the contract. Absent competition, the order is a free option down to `minPartLimit`. |
| Autonomy | `amountOutMin` (limit) and `amountOutMax` (stop) bracket. Documented default for a stop-loss is `amountOutMin = 0` | **Unbounded, at the documented default.** A stop-loss with `amountOutMin = 0` may legally be executed at any price. |
| Chainlink/Gelato-driven stops | Restrict the caller and trust it | Converted from an economic problem into a trust problem. |

**The structural fix, and it is available to Trimmy.** The free option exists because the *price* is
fixed earlier than the *execution*. If the floor is instead **recomputed at execution time from a
manipulation-resistant oracle**, the option's strike tracks the market and its value collapses to the
slippage tolerance:

```
floor = max(
    oraclePrice(now) × amount × (10_000 − maxSlippageBips) / 10_000,   // tracks the market
    minOutAbsolute                                                      // user's hard floor
)
```

Then the maximum a filler can extract per execution is `amount × maxSlippageBips / 10_000`, and the
maximum over a rule's life is `totalSellAmount × maxSlippageBips / 10_000`. **That number is the
honest headline security parameter of the product** and it should be shown to the user in the UI, in
their own currency, before they arm.

`[Inference — from the FTSOv2 properties in §1.C5 and the fee structure above]` Trimmy can do this and
1inch/CoW largely cannot, for a structural reason worth stating: they are venue-neutral protocols with
no canonical price source, whereas Flare *is* an oracle chain and FTSOv2 is a first-class, free
(`calculateFeeById` = 0) system contract. The oracle is the reason the product can be honest about the
free option.

**The residue that cannot be removed.** `maxSlippageBips` cannot be zero, because the AMM's realised
price will differ from the oracle. So there is always a nonzero option. Say the number; do not claim
zero.

---

## 3. Recommended authorization model for Trimmy

Stated precisely enough to implement. Solidity is illustrative; the invariants in §4 are normative.

### 3.1 The shape

```
                 ONE XRPL PAYMENT                         AFTERWARDS, FOREVER
                 ────────────────                         ───────────────────
  Xaman ──0xFE memo──► Core Vault
                          │  FDC attestation (p50 131s)
                          ▼
                 MasterAccountController
                          │  handleMintedFAssets
                          ▼
                  PersonalAccount.executeUserOp([
                      FXRP.approve(TrimmyExecutor, totalSellAmount),   ── the ONLY authorization
                      TrimmyExecutor.arm(RuleParams)                   ── the ONLY policy
                  ])                                                     atomic; either both or neither

                                                          anyone ──► TrimmyExecutor.execute(ruleId, …)
                                                                        ├─ re-reads FTSO
                                                                        ├─ re-checks every bound
                                                                        ├─ transferFrom(account, …)
                                                                        └─ pays msg.sender the fee
```

### 3.2 Custody: pull, never push

**Recommendation: the personal account keeps custody. Trimmy holds an allowance, not a balance.**

The alternative — arming by `FXRP.transfer(TrimmyVault, amount)` — is simpler and is what most
"deposit and forget" products do. Reject it, for three reasons:

1. **Blast radius.** With the pull model, a total compromise of the Trimmy contract loses
   `Σ min(allowance_i, balance_i)`. With the push model it loses the entire vault, including the
   balances of users whose rules are dormant or already finished.
2. **Two independent bounds.** The ERC-20 allowance and Trimmy's own `totalSellAmount` are enforced by
   two different contracts. A bug in Trimmy's accounting is still caught by the token. This is why
   invariant I-2 forbids infinite approval — infinite approval collapses the two bounds into one.
3. **Legibility.** An allowance is a standard, indexable, revocable on-chain object that block
   explorers and revoke.cash already render. A vault balance is not.

The counter-argument is real and should be stated: with the pull model, a user who moves their FXRP
elsewhere silently disarms their own rule (`transferFrom` reverts). That is a **liveness** failure, not
a safety failure, and it is the right way round.

### 3.3 The rule

```solidity
struct Rule {
    // ── identity, immutable after arm ──────────────────────────────────────
    address  account;          // the PersonalAccount; == msg.sender at arm time
    address  guardian;         // optional fast-cancel address; may ONLY cancel. 0 = none
    address  sellToken;        // FXRP
    address  buyToken;
    address  receiver;         // MUST be `account` unless explicitly named at arm time
    address  venue;            // the ONE router permitted for this rule
    bytes32  pathHash;         // keccak256(abi.encode(path)) — the route is committed, not chosen
    bytes32  salt;             // makes ruleId unique for otherwise-identical rules

    // ── trigger, re-evaluated on chain at every execution ──────────────────
    bytes21  feedId;           // FTSOv2 feed, e.g. XRP/USD
    uint8    direction;        // 0 = fire when price <= trigger  (stop-loss / buy-the-dip)
                               // 1 = fire when price >= trigger  (take-profit)
                               // 2 = time only (DCA); trigger ignored
    uint256  triggerPrice;     // normalised to the feed's decimals at arm time
    uint32   maxFeedAge;       // seconds; reject a stale feed

    // ── size bounds ────────────────────────────────────────────────────────
    uint128  partSellAmount;   // max notional per execution
    uint128  totalSellAmount;  // lifetime cap; MUST equal the approved allowance
    uint128  spent;            // running total

    // ── price bounds ───────────────────────────────────────────────────────
    uint16   maxSlippageBips;  // vs the LIVE oracle price. MUST be > 0 and <= MAX_SLIPPAGE_BIPS
    uint256  minOutAbsolute;   // per-part hard floor, oracle-independent. MUST be > 0

    // ── schedule bounds ────────────────────────────────────────────────────
    uint32   t0;               // not-before
    uint32   expiry;           // hard deadline. MUST be > t0 and <= t0 + MAX_RULE_LIFETIME
    uint32   interval;         // min seconds between executions (cooldown / DCA period)
    uint32   span;             // execution window inside each interval; MUST be <= interval
    uint32   n;                // max executions. MUST be >= 1
    uint32   executed;
    uint32   lastExecutedAt;

    // ── fee, committed at arm time ─────────────────────────────────────────
    uint64   keeperFeeFlat;    // in buyToken units
    uint16   keeperFeeBips;    // of realised output
    uint128  keeperFeeTotalCap;// lifetime cap on all fees this rule may ever pay
    uint128  keeperFeePaid;

    // ── state ──────────────────────────────────────────────────────────────
    bool     latched;          // set true the first time the price trigger is satisfied
    bool     cancelled;
}
```

`ruleId = keccak256(abi.encode(account, salt, <all immutable fields>))`.

### 3.4 Arming

```solidity
function arm(RuleParams calldata p) external returns (bytes32 ruleId) {
    // msg.sender IS the personal account (C3). No forwarder, no signature.
    _validate(p);                       // every MUST in §3.3, plus §4 invariants
    ruleId = keccak256(abi.encode(msg.sender, p.salt, p));
    require(rules[ruleId].account == address(0), RuleExists());
    // allowance must already be exactly totalSellAmount — same atomic batch (C2)
    require(
        IERC20(p.sellToken).allowance(msg.sender, address(this)) >= p.totalSellAmount,
        AllowanceMissing()
    );
    rules[ruleId] = Rule({ account: msg.sender, /* … */ });
    emit Armed(ruleId, msg.sender, p);
}
```

`arm()` makes **no external calls other than the single `allowance` view** — see C4, consequence (3).
That one `staticcall` to a known token is acceptable; anything that could transfer control is not.

### 3.5 Execution — permissionless, and re-validated from scratch

```solidity
function execute(bytes32 ruleId, uint256 minOut, bytes calldata path)
    external nonReentrant
{
    Rule storage r = rules[ruleId];

    // ── 1. authorization is entirely in storage; msg.sender is not consulted ──
    require(r.account != address(0),  UnknownRule());
    require(!r.cancelled,             Cancelled());
    require(block.timestamp >= r.t0,  NotYetActive());
    require(block.timestamp <  r.expiry, Expired());
    require(r.executed < r.n,         PartsExhausted());
    require(block.timestamp >= uint256(r.lastExecutedAt) + r.interval, Cooldown());

    // ── 2. the span window (CoW's primitive; also Jupiter's jitter budget) ──
    if (r.span < r.interval) {
        uint256 phase = (block.timestamp - r.t0) % r.interval;
        require(phase < r.span, NotWithinSpan());
    }

    // ── 3. re-derive the trigger from chain state (Chainlink's rule) ────────
    (uint256 price, int8 dec, uint64 ts) = ftso.getFeedById(r.feedId);
    require(block.timestamp - ts <= r.maxFeedAge, StaleFeed());
    if (r.direction == 0)      { require(price <= r.triggerPrice, NotTriggered()); r.latched = true; }
    else if (r.direction == 1) { require(price >= r.triggerPrice, NotTriggered()); r.latched = true; }
    // direction == 2 (DCA): schedule alone authorises. `latched` unused.

    // ── 4. size ────────────────────────────────────────────────────────────
    uint256 amount = _min(r.partSellAmount, r.totalSellAmount - r.spent);
    require(amount > 0, Exhausted());

    // ── 5. the floor: live oracle, then the user's absolute floor ──────────
    uint256 oracleOut = _quote(amount, price, dec, r.sellToken, r.buyToken);
    uint256 floorOut  = _max(
        oracleOut * (10_000 - r.maxSlippageBips) / 10_000,
        r.minOutAbsolute
    );
    require(minOut >= floorOut, MinOutTooLow());   // caller may TIGHTEN, never loosen

    // ── 6. route is committed, not chosen ──────────────────────────────────
    require(keccak256(path) == r.pathHash, WrongPath());

    // ── 7. effects BEFORE interactions ─────────────────────────────────────
    r.spent          += uint128(amount);
    r.executed       += 1;
    r.lastExecutedAt  = uint32(block.timestamp);

    // ── 8. interactions ────────────────────────────────────────────────────
    IERC20(r.sellToken).safeTransferFrom(r.account, address(this), amount);
    IERC20(r.sellToken).forceApprove(r.venue, amount);          // exact, never MAX
    uint256 out = IRouter(r.venue).swapExactTokensForTokens(
        amount, minOut, _decodePath(path), address(this), block.timestamp
    );
    IERC20(r.sellToken).forceApprove(r.venue, 0);                // always reset
    require(out >= floorOut, FloorBreached());                   // belt and braces

    // ── 9. fee — to msg.sender, capped, and it may never exceed the output ─
    uint256 fee = r.keeperFeeFlat + (out * r.keeperFeeBips) / 10_000;
    if (r.keeperFeePaid + fee > r.keeperFeeTotalCap) fee = r.keeperFeeTotalCap - r.keeperFeePaid;
    require(out > fee, DustExecution());                         // never net-negative for the user
    r.keeperFeePaid += uint128(fee);

    IERC20(r.buyToken).safeTransfer(msg.sender,  fee);
    IERC20(r.buyToken).safeTransfer(r.receiver,  out - fee);
    emit Executed(ruleId, msg.sender, amount, out, fee, price, ts);
}
```

**Step 5 is the free-option fix (§2.7). Step 3's `latched` write is the oscillation fix (§7.T7). Step
9's `msg.sender` is the liveness fix (§7.T5).**

### 3.6 Cancellation — three routes, of three different speeds

`[Verified — C1]` The user has no EVM key. This makes cancellation the hardest part of the design, and
the honest answer is that **there is no instant unilateral cancel from the XRPL side.** Three routes,
ranked by latency:

| Route | Who | Latency | Cost | Always available? |
|---|---|---|---|---|
| **R1 — expiry** | nobody; the clock | 0 (automatic) | 0 | **Yes.** Authorization lapses. This is why `expiry` is mandatory and capped. |
| **R2 — guardian cancel** | `r.guardian`, an EVM address the user names at arm time | one Flare block, ~1.87 s | one Flare tx | Only if a guardian was named |
| **R3 — XRPL cancel payment** | the XRPL key holder | **p50 131 s, p95 170 s** `[Measured — GROUND-TRUTH §18]` | ≥ 0.2 XRP + 1 drop `[Measured — GROUND-TRUTH §1]` | **Yes** |

```solidity
function cancel(bytes32 ruleId) external {
    Rule storage r = rules[ruleId];
    require(msg.sender == r.account || msg.sender == r.guardian, NotAuthorised());
    r.cancelled = true;
    emit Cancelled(ruleId, msg.sender);
    // NOTE: does NOT touch the allowance. Revoking the allowance needs its own call
    //       from the personal account (R3). `cancelled` alone is sufficient to stop
    //       Trimmy pulling, because every pull path checks it.
}

function cancelAll(address account) external {  // 1inch's epoch manager, adapted
    require(msg.sender == account || msg.sender == guardians[account], NotAuthorised());
    epoch[account] += 1;                        // every rule stores its arming epoch;
    emit EpochAdvanced(account, epoch[account]); // execute() requires r.epoch == epoch[account]
}
```

**The guardian is the design's most under-appreciated safety feature and it costs almost nothing.**
It is a strictly-cancel-only capability: a guardian can never execute, never re-arm, never change a
bound, never receive funds. A compromised guardian can only turn rules off — a denial of service, and
a user who wanted the rule off anyway is in the same position as one who never armed it. Trimmy's own
web front end can offer to be a default guardian, which turns "I want to cancel now" from a
170-second XRPL round trip into a button. The user may also name a hardware wallet or a friend.

`cancelAll` via an epoch counter is lifted directly from 1inch (§2.4). It matters here far more than
it does there, because an XRPL cancel payment costs real money and ~131 seconds — so the ability to
kill *every* rule with one payment, rather than one payment per rule, is the difference between a
usable panic button and an unusable one.

### 3.7 What is deliberately absent

A list is as load-bearing as the code. **Trimmy's executor contract has:**

- no `owner`, no `Ownable`, no `AccessControl`
- no proxy, no `upgradeTo`, no beacon, no `delegatecall` anywhere
- no `rescueTokens` / `sweep` / `emergencyWithdraw`
- no settable venue registry, no settable fee, no settable oracle address
- no pause
- **no function that accepts a caller-supplied call target or calldata**

The last one is the LI.FI lesson (§7.T2) and it is absolute. Every one of these absences is a
capability the team gives up permanently — including the ability to fix a bug — and that is the trade
being made. Mitigation for the lost upgrade path: **versioned deployment.** A new Trimmy is a new
address; users migrate by arming on it. Old rules keep running on the old contract until they expire.
This is CoW's and 1inch's model and it is the correct one for a contract holding allowances.

---

## 4. Normative invariants

These are the statements a reviewer should check, and each maps to a threat in §7.

| # | Invariant | Enforced where | Threat |
|---|---|---|---|
| **I-1** | `execute()` has **no** caller restriction. `msg.sender` is used only as the fee recipient. | absence of a modifier | T1, T5 |
| **I-2** | The arming allowance is **exactly** `totalSellAmount`. Never `type(uint256).max`. | front end + `arm()` check + Plimsoll preflight | T1, T2 |
| **I-3** | Every authorization input comes from storage set at arm time, or from FTSO read at execution time. **Nothing the caller supplies may loosen a bound** — `minOut` and `path` may only tighten or match. | `execute()` steps 3, 5, 6 | T1, T3 |
| **I-4** | `expiry` is mandatory, `expiry > t0`, and `expiry - t0 <= MAX_RULE_LIFETIME`. There is no never-expiring rule. | `_validate()` | T6, T1 |
| **I-5** | `maxSlippageBips > 0` and `<= MAX_SLIPPAGE_BIPS`; `minOutAbsolute > 0`. A zero floor is unrepresentable. | `_validate()` | T3, T4 |
| **I-6** | Effects (`spent`, `executed`, `lastExecutedAt`) are written **before** any external call, and `execute()` is `nonReentrant`. | `execute()` step 7 | T9 |
| **I-7** | Trimmy never reimburses gas. The fee is denominated in `buyToken` and fixed at arm time. | fee model | T7, T10 |
| **I-8** | Approval to the venue is set to the exact `amount` and reset to `0` in the same call. | `execute()` step 8 | T2 |
| **I-9** | `arm()` performs no external call that can transfer control. | `arm()` | T9 |
| **I-10** | `require(out > fee)`. A rule may never execute at a net loss to the user. | `execute()` step 9 | T7 |
| **I-11** | The contract is non-upgradeable and has no privileged role. | absence | T2 |
| **I-12** | `receiver` is `account` unless the user explicitly named another address, and Plimsoll displays it before the XRPL payment is signed. | `_validate()` + preflight | T6 |

---

## 5. Design decisions that need a human to choose

### 5.1 `latched` — should a stop-loss be a one-way door?

Recommended: **yes.** Once `price <= triggerPrice` has been observed once, `latched = true` and
subsequent parts check only the schedule and the floor, not the trigger. This deletes the oscillation
griefing vector entirely (T7). The cost: if the price dips below the trigger for one block and
recovers, a multi-part stop-loss will keep selling. That is arguably what a stop-loss *means* — but it
is a product decision, and the alternative (re-check the trigger every part) trades that away for
oscillation exposure. **My recommendation is latch, with `n = 1` as the default for stop-loss rules**,
so the common case has no oscillation surface at all.

### 5.2 `span` for stop-losses

`span` is a jitter budget for DCA (§2.6) and a griefing bound for everything. But a stop-loss with a
600-second span is a stop-loss that may fire up to 600 seconds late. Recommended: **`span = interval`
(i.e. no window restriction) for `direction ∈ {0,1}`, and `span << interval` for `direction = 2`
(DCA).** Price-triggered rules are already gated by a condition that is hard to predict; time-triggered
rules are perfectly predictable and need the jitter.

### 5.3 Do not ship a general predicate language in v1

1inch's `arbitraryStaticCall` and CoW's `IConditionalOrder` are the right long-term shape. They are
also the largest possible attack surface, because a user-supplied condition is a user-supplied
program. For a 8-day build, ship two `direction` values plus a time mode, hard-coded. Note the v2
shape in the README so a judge sees the trajectory. If a predicate system is added later it **must**
be `staticcall`-only, exactly as 1inch constrains it.

### 5.4 Arming two rules requires one batch, not two payments

`[Measured — GROUND-TRUTH §8.2, §6.2, and `getNonce` live-read]` The personal account nonce increments
by exactly one per instruction, and `handleMintedFAssets` reverts `InvalidNonce(current, given)` if
they disagree. Two arming payments built against the same `getNonce` reading means **the second
strands** — the XRP sits at the Core Vault and needs a `0xE0` skip-memo recovery payment to free it
(GROUND-TRUTH §11).

**Therefore: Trimmy must arm N rules in ONE `executeUserOp` batch, or serialise arming payments and
re-read `getNonce` between them.** This is an operational requirement with money attached, not a nicety.
It is also exactly what Plimsoll's `BR-5` already validates.

### 5.5 Do not pin an executor on the arming payment

`[Measured — GROUND-TRUTH §1, §10]` `getDirectMintingOthersCanExecuteAfterSeconds = 7200`. Naming a
preferred executor that then fails to act strands the arming payment for **two hours** before anyone
else may help. Coston2 runs a standing public executor
(`0x103b384064ae85577127097A7cCadfd6fb13f437`) that minted 30/30 test payments at p50 131 s.

Letting a third party execute the arming is **safe**, and this is worth spelling out to a judge:
the `0xFE` memo commits to `keccak256(PackedUserOperation)` and a mismatch reverts with
`CustomInstructionHashMismatch(bytes32,bytes32)` (selector `0xad79273d`, `[Measured]` via `cast sig`).
The executor is a courier, not a party. `[Measured — GROUND-TRUTH §11.4]` A third-party executor
already carried out a recovery that Plimsoll planned, which is the property demonstrated in the wild.

Corollary: `getExecutor(PA)` currently returns `0x0` for the test account `[Measured]`, i.e. unpinned.
If a user *has* pinned a dead executor, arming and cancelling both stall — and the escape is the
`0xD0`/`0xD1` pin/unpin opcodes, which `[Measured — GROUND-TRUTH §8.5]` deliberately bypass the
executor check for exactly this reason.

---

## 6. Ranked threat model

Ranked by **expected loss = severity × likelihood**, not by severity alone.

### T1 — Malicious or compromised keeper · severity if unmitigated: **total** · after mitigation: **zero**

**The attack.** Trimmy's keeper key leaks. The attacker executes rules at the worst possible moments,
drains fees, or (if the design were naive) calls a privileged executor entry point and moves user
funds to itself.

**Maximum damage, by design choice:**

| Design | Max damage on keeper key leak |
|---|---|
| Keeper is the only permitted caller and supplies `minOut` | **Everything.** `minOut = 0` drains every armed account through a self-sandwiched swap. |
| Keeper-only caller, `minOut` derived on-chain | `Σ (allowance_i × maxSlippageBips)` per execution cycle, plus indefinite censorship |
| **Permissionless `execute`, all bounds on-chain (recommended)** | **Zero.** The leaked key can do nothing an anonymous address could not already do. |

**Mitigation: I-1 plus I-3.** Because the trigger is FTSO — on-chain, free to read, updated every
~1.8 s — there is no off-chain information required to authorise an execution. Therefore there is no
reason to privilege anyone. **The keeper key becomes a convenience, not a capability.** Trimmy's keeper
exists to make execution *timely*; the contract exists to make it *safe*; those are separate.

Per-rule allowance vs blanket approval: **per-rule (I-2)**. Destination whitelisting: **`receiver` and
`venue` and `pathHash` committed at arm time (I-12, §3.3)**. Slippage bounds on-chain: **I-5, §3.5 step
5**. Max notional per execution: **`partSellAmount`**. Cooldowns: **`interval` + `span`**.

**Adversarial note.** Permissionless execution moves the risk rather than deleting it: now *anyone*
is the keeper, which is T3 and T7. Those are bounded (below); an unbounded keeper capability is not.
That trade is the right one and it is the trade the whole design turns on.

### T2 — Compromised or malicious Trimmy contract · severity: **bounded-total** · likelihood: low

**The attack.** This is the rug, and it is the one users are actually right to fear. Precedents:

- `[Verified — CoinDesk 2024-07-16, SolidityScan / QuillAudits analyses]` **LI.FI, 2024-07-16,
  $11.6M.** A newly added `GasZipFacet` exposed `depositToGasZipERC20()`, which passed user-controlled
  `_swapData` (both `callTo` and `callData`) into `LibSwap.swap`, which performs a low-level call. The
  attacker crafted `transferFrom()` calldata and drained **only wallets that had granted infinite
  approvals**. 153 wallets, Ethereum and Arbitrum. The facet was live for five days.
- `[Verified — secondary, revoke.cash exploits index]` **Squid**: ~$623K reachable because approvals
  went to `SquidMulticall` rather than the router — an operational mistake, not a code bug, with an
  identical outcome.

**Mitigations: I-2 (never infinite), I-11 (no admin, no upgrade), §3.7 (no arbitrary-call surface),
I-8 (exact approval to the venue, reset to zero).**

The LI.FI shape is worth restating as a rule because it recurs: **an allowance to a contract that can
be made to call an arbitrary target with arbitrary calldata is equivalent to handing over the tokens.**
Trimmy accepts `path` from the caller, which looks like the same shape — and that is exactly why
`pathHash` is committed at arm time (I-3, step 6). The caller supplies the path only so it does not
have to be stored; the contract checks it against a commitment. A reviewer should verify that no other
caller-supplied bytes reach a `call`.

Blast radius with these mitigations: `Σ min(allowance_i, balance_i)` over armed rules, which is
bounded, user-chosen, visible, and decays automatically as rules expire (I-4).

### T3 — MEV: sandwiching the executed swap · severity: **bounded** · likelihood: **high**

**The attack.** The executed swap hits an AMM. A searcher buys before it and sells after, capturing the
price impact. Trimmy's own keeper can do this to its own executions, which is the worst case because it
controls the timing.

**What is measurable about Flare today.** `[Measured — 2026-08-06, public Coston2 RPC]`

```
txpool_content                    -> -32601, method does not exist
txpool_status                     -> -32601, method does not exist
eth_newPendingTransactionFilter   -> accepted, returns a filter id
eth_getFilterChanges (5 polls, 3s apart, 15s total) -> 0 hashes every time
meanwhile: 23 transactions landed across the 10 blocks spanning that window (~19 s)
```

`[Inference]` The public RPC accepts the pending-transaction filter but never reports a pending
transaction while real transactions are landing, so **the public Coston2 endpoint does not surface a
pending pool.** `[Unverified]` This says nothing about what a validator sees. Flare uses Avalanche
Snowman++, where the next N block proposers are selected in advance by stake — so a proposer knows in
advance that it will propose, and a searcher co-located with proposers has a real advantage.
**Experiment that would settle it:** submit a transaction with a deliberately low tip via one public
RPC and poll `eth_getFilterChanges` on a *different* provider's endpoint; if the hash appears before
the transaction is mined, a propagating public pool exists.

**Mitigations, in order of strength:**

1. **The oracle-derived floor (§2.7, step 5).** This is the only one that bounds the loss rather than
   reducing its probability. Maximum extraction per execution is `amount × maxSlippageBips / 10_000`,
   full stop, regardless of who executes or how. **Put this number in the UI.**
2. **Small `partSellAmount`.** Extraction is proportional to notional; splitting a large rule into
   parts reduces both price impact and per-execution extraction. This is why the CoW TWAP shape is the
   right base struct even for a stop-loss.
3. **`span` jitter for time-triggered rules (§2.6, §5.2).**
4. **`deadline = block.timestamp`** on the router call, so a delayed inclusion reverts rather than
   executing at a stale price.

**What Trimmy must not claim.** Trimmy is not CoW. There is no batch auction, no uniform clearing
price, no solver competition on Flare. The honest statement is *"we bound the extractable amount to a
number you chose; we do not eliminate it."*

### T4 — Oracle manipulation and staleness · severity: **high** · likelihood: **low (manipulation), medium (staleness)**

**Manipulation.** `[Verified — flare.network/news/ftsov2-more-data-delivered-faster,
dev.flare.network/ftso/overview]` FTSOv2 block-latency feeds update every ~1.8 s using a
manipulation-resistant verifiable-randomness algorithm; anchor feeds run a full commit-reveal across
~100 independent data providers every 90 s, and *"data providers are only rewarded if the block-latency
feeds align with the anchor feeds every voting epoch."* Manipulating this requires corrupting a
significant share of the provider set. It is materially harder than moving an AMM spot price.

**The asymmetry that matters.** An attacker who cannot move FTSO can still move the AMM freely. This is
why the floor must be derived from FTSO and **never** from the venue's own reserves. State it as a
rule: **trigger from FTSO, floor from FTSO, execute on the AMM, and never let the AMM tell you what
anything is worth.** A design that computed `minOut` from `getAmountsOut()` on the venue would be
trivially defeated by a flash-loan.

**Staleness — this one is real and I measured it.** `[Measured — 2026-08-06, XRP/USD on Coston2
FtsoV2 `0xC4e9…304d`, eight reads two seconds apart]`

```
wall=…065  value=1049423  dec=6  ts=…036     <-- 29 seconds stale at read time
wall=…068  value=1049423  dec=6  ts=…068
wall=…071  value=1049423  dec=6  ts=…071
wall=…075  value=1049422  dec=6  ts=…074
wall=…078  value=1049422  dec=6  ts=…074
wall=…081  value=1049550  dec=6  ts=…079
wall=…084  value=1049550  dec=6  ts=…083
wall=…088  value=1049550  dec=6  ts=…088
```

The first read returned a timestamp **29 seconds old**. Most reads were 0–4 seconds old. So the
returned `_timestamp` is not simply "now" — **`maxFeedAge` must be a genuine check with a real
threshold, and a design that ignores the third return value would silently trade on a half-minute-old
price during exactly the volatility where it matters most.**

Recommended `maxFeedAge`: **60 s** for price-triggered rules. Note this is a *hard* bound: exceeding it
reverts, which converts a correctness risk into a liveness risk (T5) — the right direction.

`[Unverified]` Whether the 29-second observation is an RPC-caching artefact, a genuine feed gap, or
normal Coston2 behaviour. **Experiment:** sample `getFeedById` once per second for one hour against
two independent RPC endpoints, and histogram `block.timestamp - ts`. Also read the same feed from
inside a contract via `eth_call` at a pinned block to eliminate the RPC layer. This should be done
before choosing the production `maxFeedAge`.

Additional oracle hazards to handle:

- **Decimals.** `getFeedById` returns `int8 _decimals` — **signed**, so it can be negative. Normalise
  defensively; do not assume 6.
- **Feed ID migration.** `getFeedIdChanges()` exists in the interface and returns `(bytes21,bytes21)[]`
  `[Verified — SDK binding, artifacts 0.1.52]`. A feed ID can be *retired*. A long-lived rule pinned to
  a retired feed becomes unexecutable. Mitigation: bounded `MAX_RULE_LIFETIME` (I-4), and a preflight
  warning.
- **Fee.** `getFeedById` is `payable` and `calculateFeeById` currently returns **0** `[Measured]`, but
  Flare's own migration guide says to use `FeeCalculator` and *"be prepared for potential future
  changes."* A rule that becomes unexecutable because the oracle started charging is a real failure
  mode. `execute()` should call `calculateFeeById` and forward the value, funded by the keeper.

### T5 — Keeper liveness failure · severity: **high (opportunity cost)** · likelihood: **medium**

**The attack, which is not an attack.** The price crosses the trigger and nothing happens. The user's
stop-loss does not fire. Who is accountable?

**Answer: nobody, and Trimmy must say so in those words.** With permissionless execution (I-1) there is
no party under an obligation. What exists instead is an economic incentive: an armed, triggered rule is
an option that anyone may exercise for `keeperFeeFlat + out × keeperFeeBips`.

**This project already has hard evidence for how that fails.** `[Measured — GROUND-TRUTH §10.3, §18]`
On Coston2, 30 of 30 direct-mint payments that left the executor a full 100,000 UBA fee were executed,
p50 131 s. A 0.05 XRP payment that left the executor **nothing** sat unexecuted for over five minutes
and had to be executed by us. The conclusion recorded there generalises exactly:

> *"A latency figure gathered only from payments somebody wanted to execute says nothing about the ones
> nobody does."*

**Mitigations:**

1. **Permissionless execution (I-1).** Trimmy's keeper is one participant. If it dies, the rule is
   still executable by anyone.
2. **A preflight refusal.** Plimsoll must **refuse to arm a rule whose fee would not cover expected
   execution gas at arm time**, by the same logic and with the same severity as it refuses a payment
   below the FAssets fee floor. This is a direct reuse of Plimsoll's existing
   `paymentConsumedEntirelyAsFee` reasoning.
3. **Fee in `buyToken`, not gas reimbursement (I-7).** A flat fee is predictable to a keeper, which is
   what makes third parties willing to run one.
4. **Publish the incentive.** The rule's fee is public on-chain; a competing keeper can compute its
   margin without asking anyone.

**The trade-off, stated honestly.** Permissionless execution costs three things: (i) it makes rules
public, which is T8; (ii) it means anyone may execute at the least favourable moment within the bounds,
which is T3 and T7; (iii) it removes any party to complain to. The alternative — a designated keeper
with an SLA — costs T1 in full. For a self-custody product aimed at users whose entire reason for being
here is not trusting a custodian, **permissionless is the only coherent choice.**

### T6 — Approval revocation and cancellation · severity: **high** · likelihood: medium

**The attack.** The user changes their mind, or realises a rule is mispriced, and cannot stop it.

**The hard constraint.** `[Measured — C1, GROUND-TRUTH §18]` Cancelling from the XRPL side costs one
payment (≥ 0.2 XRP + 1 drop) and p50 **131 s**, p95 **170 s**. During that window an execution that
meets every on-chain condition may legally occur. **There is no instant unilateral cancel and Trimmy
must not imply otherwise.**

**Mitigations, in the order they should be presented to a user:**

1. **`expiry` is mandatory and capped (I-4).** The worst case is bounded in time by a number the user
   chose. A rule that cannot be cancelled will still stop.
2. **Guardian (§3.6, R2).** One Flare block. This is the answer for anyone willing to name an EVM
   address, and Trimmy's front end should offer to be one by default with the trade-off stated
   plainly: *"we can turn your rules off; we can never make them run, change them, or take your
   money."*
3. **`cancelAll` epoch counter (§3.6).** One payment kills every rule, not one payment per rule.
4. **The allowance is the second lock.** `cancel()` sets `cancelled` and every path checks it; a user
   who wants the *allowance* gone as well needs an XRPL payment carrying
   `FXRP.approve(Trimmy, 0)`. Because the allowance is exactly `totalSellAmount` and not infinite
   (I-2), leaving it in place after cancelling is not a standing risk of unbounded size.

**Is a cancel front-runnable?** Yes, and it does not matter much. A keeper watching XRPL sees the
cancel payment ~131 s before it lands on Flare and can execute in that window — **but only if every
on-chain condition holds**, which is precisely the set of executions the user already authorised. The
loss is the difference between "cancelled at T" and "cancelled at T+131s", not an unbounded loss. The
guardian route closes even this.

**The other half of T6: the arming payment itself.** This is the highest-consequence single moment in
the product. The user is signing an XRPL payment whose visible content is 42 opaque bytes committing to
`keccak256(PackedUserOperation)`. A malicious or compromised Trimmy front end can put
`FXRP.approve(attacker, MAX)` in that batch. **Plimsoll must decode the batch and display, in plain
language, every `approve` target and amount, the `receiver`, the `venue`, and the total the rule may
ever spend — before the payment is signed.** This is not a nice-to-have; it is the reason the
architecture is defensible at all, and it is exactly what `BR-5` already specifies.

### T7 — Griefing · severity: **medium** · likelihood: **medium**

Four distinct sub-attacks. They have different mitigations and must not be conflated.

**T7a — Oscillation around the threshold.** Price hovers at `triggerPrice`. An attacker executes one
part every `interval`, each charging `keeperFeeFlat`, bleeding the user.
*Mitigation: the `latched` one-way door (§5.1), plus `n`, plus `keeperFeeTotalCap`, plus I-10
(`out > fee`).* With `latched`, the trigger is checked once ever; after that the rule is simply a
scheduled sell, and oscillation has no purchase. This is strictly stronger than Chainlink's
*"ensure that `checkUpkeep` remains true until execution."*

**T7b — Repeatedly triggering fee-charging executions.** Even without oscillation, an attacker may
execute every part the instant it becomes legal, at exactly `floorOut`, capturing
`maxSlippageBips` each time.
*Mitigation: none that removes it — this is inherent to permissionless execution.* The bound is
`totalSellAmount × maxSlippageBips / 10_000` plus `keeperFeeTotalCap`, and both are user-chosen and
displayed. `interval` and `span` limit the *rate* but not the *total*. **State the total.**

**T7c — Dust attacks.** Executing a part whose output is smaller than `keeperFeeFlat`, so the user pays
more than they receive.
*Mitigation: I-10 `require(out > fee)`, plus a minimum `partSellAmount` validated at arm time such that
the expected output at the trigger price is some multiple (say 20×) of `keeperFeeFlat`.* This is the
FAssets dead-zone lesson transplanted: `[Measured — GROUND-TRUTH §1]` a direct mint of 0.1–0.2 XRP
delivers the recipient exactly zero and emits a **success** event. The failure mode Trimmy must avoid is
identical in shape — a transaction that succeeds and delivers nothing.

**T7d — Forcing execution at a bad time.** An attacker executes during a brief adverse tick.
*Mitigation: the floor (step 5) makes "bad" mean "at most `maxSlippageBips` worse than the live oracle",
and `maxFeedAge` makes "live" mean live.* Combined with `span` jitter for DCA, this is as good as it
gets without a batch auction.

### T8 — Information leakage · severity: **medium** · likelihood: **certain**

**Not in the brief's list, and it should be.** Every armed Trimmy rule is fully public on-chain,
including the trigger price, the size, and the account. That is the unavoidable price of permissionless
execution — a permissionlessly-verifiable condition is a publicly-readable condition.

Consequences: (i) a searcher can pre-position against a large known stop-loss, which is a strictly
worse position than Jupiter's off-chain private orders `[Verified — §2.6]`; (ii) a cluster of stop
losses at a round number is a visible liquidation cascade, which is a systemic risk the moment Trimmy
has volume.

**Mitigations:** split large rules into parts (small `partSellAmount`); avoid round-number triggers in
the UI's suggested defaults; and — the honest long-term answer — **this is the strongest argument for
the FCC/TEE half of the product.** A trigger evaluated inside a Confidential Space enclave is not
public. That is a real, defensible reason for Bounty 2 to exist beyond "we wanted a second entry", and
it should be the framing.

Trade-off to state: a TEE-evaluated trigger is **not** permissionlessly verifiable, so it re-introduces
T1 and T5 in the amount of whatever the enclave attests. The correct hybrid is *private trigger, public
bounds*: the enclave may say "fire now", but the contract still enforces `floorOut`,
`partSellAmount`, `expiry`, `receiver` and `venue` exactly as before. **A TEE may choose the moment; it
may never choose the amount, the price, or the destination.**

### T9 — Reentrancy · severity: **high** · likelihood: low

Two distinct contexts, and the Flare-specific one is the subtler.

**T9a — the arming context.** `[Verified — C4]` `Reentrancy.nonReentrantAfter()` clears the
AssetManager's guard immediately before `handleMintedFAssets`, deliberately, so that a smart account
can redeem inside its own instruction. Flare's safety argument is positional — *"This is safe, because
`handleMintedFAssets` is the last operation"* — and the library confirms it is a bare write of
`_NOT_ENTERED`, not a save/restore.

So during arming, `AssetManager` is re-enterable. **Mitigation: I-9 — `arm()` makes no external call
that can transfer control.** Additionally `[Verified]` `PersonalAccount` is
`ReentrancyGuardTransient` and `executeUserOp` is `nonReentrant`, so a hostile token cannot induce a
nested `executeUserOp`. The two together mean the open AssetManager guard is unreachable from Trimmy's
code, by construction rather than by luck.

**T9b — the execution context.** `execute()` does `transferFrom → approve → external swap → transfer`.
The precedent is `[Verified — secondary, Blockaid, "Your DeFi Protocol's Automation Layer is The Next
Attack Target"]` **GMX, July 2025, $42M**: an attacker submitted a "decrease position" order that
GMX's *keeper bot* picked up, and *"the malicious contract reentered the vault before state updates
were complete"*, minting and redeeming GLP at manipulated prices. `[Unverified]` I have not read the
GMX postmortem primary source; date, amount and mechanism are as reported by Blockaid.

The generalisable lesson is exact and it is the reason I-6 exists: **a keeper bot picking up an order
is an attacker-chosen entry point into your contract.** Trimmy's `execute()` is called with an
attacker-chosen `ruleId`, at an attacker-chosen block, in an attacker-chosen call stack.

*Mitigations: I-6 (effects before interactions — `spent`, `executed` and `lastExecutedAt` are written
before `transferFrom`), a `nonReentrant` guard on `execute()`, `forceApprove(venue, 0)` after the swap
(I-8), and Blockaid's own summary rule: assume "every receiver is adversarial".* Note that
`buyToken` may be an arbitrary ERC-20 chosen by the user at arm time — so the two `safeTransfer` calls
at step 9 are calls into potentially hostile code, after all state is settled. That ordering is
deliberate.

### T10 — Gas-price and fee-model griefing · severity: **low** · likelihood: low

Autonomy needed `gasPriceCheck(maxGasPrice)` because it reimburses gas at cost+30% `[Verified — §2.1]`.
**Trimmy deletes the vector by not reimbursing gas (I-7).** The keeper bears its own gas and earns a
fee fixed at arm time; if gas spikes past the fee, execution simply stops being profitable, which is
T5 (liveness) rather than a loss. `[Measured]` Coston2 base fee 500 gwei, suggested priority 150 gwei,
denominated in FLR — low absolute cost, but the *ratio* to the fee is what matters and it must be
checked at arm time by the preflight.

---

## 7. Breaking my own design

Six attempts. Two of them found real problems.

**A1 — "Make `execute` permissionless and the fee goes to `msg.sender`; so a keeper front-runs
Trimmy's own keeper for every execution."** *Correct, and intended.* That is competition, and it is the
mechanism that provides liveness. Trimmy's business model must therefore not be "we earn the execution
fee" — it will be competed to the gas cost. **The revenue line must be the protocol fee taken from the
user's output at execution (a fixed `bips` that goes to a Trimmy fee address committed at arm time),
which is *not* contestable because it is part of the rule.** The pivot memo's "flat fee per executed
rule, 0.1–0.3%" is compatible with this, but the memo does not distinguish the two fees and it must.
**This is a finding: `keeperFee` and `protocolFee` are different fees with different economics and the
contract needs both.**

**A2 — "The oracle floor makes a stop-loss unfillable in a real crash, because the AMM will be worse
than the oracle by more than `maxSlippageBips` exactly when the user needs the fill."** *Correct, and
this is the sharpest criticism of the design.* A protective stop that does not fire in a crash is worse
than no stop, because the user believed they were protected. Options: (i) widen `maxSlippageBips` and
accept more extraction; (ii) let `maxSlippageBips` widen with time-since-trigger — a Dutch decay from
tight to loose, which is exactly what CoW's `clogs` (Dutch auction conditional order) does; (iii) accept
non-execution and warn. **Recommendation: (ii), a Dutch-decaying floor** — start at
`maxSlippageBips`, widen linearly to `maxSlippageBipsCrash` over `decayWindow` seconds after the latch.
This preserves the free-option bound in normal conditions and degrades gracefully. It is one extra
storage word and one extra line of arithmetic. `[Inference — from the CoW Dutch-auction template's
existence and the mechanics above; the specific decay curve is unvalidated.]`

**A3 — "The guardian can grief by cancelling everything."** Yes. It is a denial of service, and the
user's fallback is the XRPL route (R3, 131 s). Optional and off by default for anyone who does not want
it. Acceptable.

**A4 — "`pathHash` commits the route, so if the venue's liquidity migrates the rule becomes
unexecutable."** Correct, and it is a liveness failure not a safety one. Mitigated by bounded
`MAX_RULE_LIFETIME` (I-4). The alternative — letting the keeper choose the route — reintroduces the
LI.FI shape (T2). **Keep the commitment.** A v2 could commit to a *set* of routes via a merkle root,
exactly as ComposableCoW does for orders.

**A5 — "`latched` means a one-block price wick permanently arms a multi-part sell."** Correct, and it
is the cost of deleting T7a. Mitigated by defaulting stop-loss rules to `n = 1`, and by `maxFeedAge`
plus FTSO's anchor-feed alignment making a one-block wick in the *oracle* much less likely than in an
AMM. Worth an explicit UI warning for `n > 1` stop-losses.

**A6 — "The whole thing rests on the arming batch being what the user thinks it is, and the user is
signing 42 opaque bytes in Xaman."** *This is the real remaining risk and no contract-level mitigation
reaches it.* The mitigation is entirely Plimsoll: decode, simulate, display, refuse. Two honest
limits, both already recorded: `[Measured — GROUND-TRUTH §4]` simulation fidelity is **partial** — the
reentrancy-re-enabled context, the memo nonce, the executor fee payment, and a first-ever mint before
CREATE2 deployment are all unreproducible, so *"a success from a partial simulation is not evidence the
real batch succeeds; a revert is the more trustworthy direction."* And Plimsoll's guarantee is about
*this* batch, not about whether the Trimmy contract it approves is honest — that is T2, and its answer
is verified source plus no admin plus no upgrade, not simulation.

---

## 8. Open questions, each with the experiment that settles it

1. **FTSO staleness distribution.** One read was 29 s old `[Measured]`. → Sample `getFeedById` at 1 Hz
   for one hour against two independent RPCs and from inside a contract at pinned blocks; histogram
   `block.timestamp - ts`. Choose `maxFeedAge` from the p99. *Blocks: the production `maxFeedAge`.*
2. **Does Flare have a propagating public mempool?** `txpool_*` absent, pending filter returns nothing
   `[Measured]`. → Submit a low-tip transaction via RPC A, poll `eth_getFilterChanges` on RPC B; if the
   hash appears pre-inclusion, a public pool exists. *Blocks: how loudly Trimmy may claim MEV
   resistance.*
3. **Which venue, and does it exist on Coston2?** The whole swap leg is unspecified here. → Enumerate
   routers on Coston2, confirm FXRP liquidity depth, and measure realised slippage for the intended
   `partSellAmount`. *Blocks: whether `maxSlippageBips` defaults are honest.*
4. **Balmy `dca-v2-core` swap authorization.** `[Unverified]` → Read `DCAHub.sol::swap` and
   `IDCAHubSwapCallee`; determine who supplies the route and how minimum output is derived. *Blocks:
   nothing; it is confirmation of an already-converged design.*
5. **Gas cost of `execute()` on Flare, and therefore the minimum viable `keeperFeeFlat`.** → Deploy to
   Coston2 and measure. *Blocks: the preflight's refuse-to-arm threshold (T5 mitigation 2), which is a
   correctness requirement, not a tuning parameter.*
6. **The Dutch-decaying floor (A2).** `[Inference]` → Backtest the decay curve against historical
   XRP/USD volatility and realised AMM depth. *Blocks: whether a crash-time stop actually fills.*
7. **GMX July-2025 mechanism.** `[Unverified]` — reported by a secondary source only. → Read the
   primary postmortem before citing it in any submission material.

---

## 9. Implementation checklist

- [ ] `TrimmyExecutor` deployed non-upgradeable, no owner, no proxy, no `delegatecall`, no sweep (I-11, §3.7)
- [ ] `execute()` has no caller restriction; `msg.sender` used only as fee recipient (I-1)
- [ ] Every bound read from storage or FTSO; `minOut` and `path` may only tighten or match (I-3)
- [ ] `arm()` requires `allowance == totalSellAmount` exactly; front end never emits an infinite approve (I-2)
- [ ] `expiry` mandatory, `<= MAX_RULE_LIFETIME` (I-4)
- [ ] `maxSlippageBips > 0`, `minOutAbsolute > 0` — a zero floor is unrepresentable (I-5)
- [ ] `receiver`, `venue`, `pathHash` committed at arm time (I-12)
- [ ] Effects before interactions; `nonReentrant` on `execute()` (I-6)
- [ ] `forceApprove(venue, amount)` then `forceApprove(venue, 0)` (I-8)
- [ ] `require(out > fee)` (I-10)
- [ ] `arm()` makes no control-transferring external call (I-9)
- [ ] `maxFeedAge` enforced against `getFeedById`'s third return value; `int8` decimals normalised defensively
- [ ] `calculateFeeById` forwarded as `msg.value` to the payable FTSO read
- [ ] `latched` one-way door; stop-loss defaults to `n = 1`
- [ ] `span <= interval` enforced; jitter for `direction = 2`
- [ ] Guardian is cancel-only; `cancelAll` epoch counter present
- [ ] Protocol fee and keeper fee are **separate** fields (A1)
- [ ] Plimsoll refuses to arm when the fee cannot cover expected gas (T5)
- [ ] Plimsoll decodes and displays approve target/amount, receiver, venue, lifetime cap before signing (T6)
- [ ] Multiple rules armed in ONE `executeUserOp` batch, or `getNonce` re-read between payments (§5.4)
- [ ] Arming payment does **not** pin an executor (§5.5)
- [ ] Arming payment clears the 0.2 XRP + 1 drop floor (GROUND-TRUTH §1)
- [ ] UI displays `totalSellAmount × maxSlippageBips / 10_000` in the user's currency as the
      **maximum amount a keeper can extract over this rule's life** (T3, T7b)

---

## 10. Sources

Read directly as source:

- `flare-foundation/fassets` — `contracts/openzeppelin/library/Reentrancy.sol` (raw)
- Coston2 verified source, `DirectMintingFacet` `0x4aFaEda2AC4442cD10Ac601622Eee0dF5DF78eeF`
- Coston2 verified source, `PersonalAccount` `0xe900cf0C3f1320816700c669B002835aCc9A93A6`
- `Autonomy-Network/uniV2-limits-stops@master` — `contracts/UniV2LimitsStops.sol` (raw, 614 lines)
- `cowprotocol/composable-cow@main` — `src/types/twap/TWAP.sol`, `src/types/twap/libraries/TWAPOrder.sol` (raw)
- `sdk/packages/flare_network_periphery/lib/src/ftso_v2_interface.g.dart`,
  `.../i_personal_account.g.dart` (generated from `@flarenetwork/flare-periphery-contract-artifacts@0.1.52`)
- `plimsoll/docs/GROUND-TRUTH.md` §§1, 4, 5, 6, 7, 8, 10, 11, 18

Read as documentation:

- https://docs.cow.fi/cow-protocol/reference/contracts/periphery/composable-cow
- https://docs.cow.fi/cow-protocol/concepts/order-types/programmatic-orders
- https://docs.chain.link/chainlink-automation/concepts/best-practice
- https://docs.gelato.cloud/web3-functions/security-considerations/dedicated-msg-sender
- https://docs.autonomynetwork.io/autonomy-docs and its `llms-full.txt`
- https://github.com/1inch/limit-order-protocol/blob/master/description.md
- https://betastation.jup.ag/guides/dca/how-dca-work
- https://dev.flare.network/ftso/overview · https://flare.network/news/ftsov2-more-data-delivered-faster

Incidents (secondary sources, labelled as such in text):

- LI.FI 2024-07-16 — https://www.coindesk.com/business/2024/07/16/defi-protocol-lifi-struck-by-8m-exploit ·
  https://blog.solidityscan.com/li-fi-hack-analysis-521388128d22/
- GMX 2025-07 · Squid · Summer.fi — https://www.blockaid.io/blog/your-defi-protocols-automation-layer-is-the-next-attack-target ·
  https://revoke.cash/exploits

Live chain: `https://coston2-api.flare.network/ext/C/rpc`, chain ID 114, all reads 2026-08-06.
