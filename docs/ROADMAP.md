# Trimmy — roadmap

**Written 2026-08-07.** Closes critique finding **M8** ("there is no integrated critical path across
the two bounties"), which was correct: `fcc-extension.md` had an 8-task plan, Bounty 1 had none, and
nothing connected them.

Submission closes **2026-08-14 19:59**. That is a fact about the calendar, not an argument for
shipping less. Nothing in this document is scoped down to fit it; where something is genuinely
incomplete on the day, the honest move is to say so and keep working, not to have quietly cut it
months of design earlier.

Status legend: **✅ done** · **▶ in progress** · **○ not started** · **⛔ blocked**

---

## 0. The shape of the thing

Two bounties, $6,000 each, from one codebase.

| | Bounty 1 — Interoperable Asset Products | Bounty 2 — Confidential Compute Apps |
|---|---|---|
| What | XRPL payment arms a rule; rule executes itself | Rules that fire on data FDC structurally cannot reach |
| Core artefact | `Trimmy.sol` + keeper + arming front end | FCC TEE extension + `PRIVATE` trigger |
| Trust model | permissionless, keeper trusted with nothing | enclave-gated, operator can censor |
| Depends on | FTSO, FAssets, Smart Accounts, a swap venue | everything in Bounty 1, plus the extension |

**Bounty 2 strictly depends on Bounty 1.** A private trigger is a trigger on a rule; without the rule
engine there is nothing for the enclave to gate. So the order is not negotiable — Bounty 1's core
must work before the extension is worth building.

---

## 1. Foundations — ✅ complete

| | Item | Evidence |
|---|---|---|
| ✅ | Research pack, adversarial critique, red-team attack | `research/00-critique.md`, `research/02-ARCHITECTURE-ATTACK.md` |
| ✅ | Measured chain facts with reproducing commands | `docs/GROUND-TRUTH.md` |
| ✅ | Normative architecture closing every red-team finding | `research/01-ARCHITECTURE.md` |
| ✅ | Toolchain pinned to verified-latest | `contracts/foundry.toml` |
| ✅ | `Quote.sol` — two-legged FTSO valuation | 16 tests, incl. 40k fuzz runs + 256-vector Python differential |
| ✅ | Venue interfaces read off-chain, not assumed | GROUND-TRUTH §4a-bis, §4d |
| ✅ | `Trimmy.sol` — arm / execute / claim / cancel | 25 tests, each naming the finding it defends |

**41 tests green.** Four defects were caught by process rather than by luck: 12 unsafe money-math
typecasts (`deny = "warnings"`), a silently-ignored `fs_permissions` key in the wrong TOML table,
`vm.expectRevert` not seeing internal library reverts, and `via_ir` hoisting `block.timestamp` out of
a loop so `vm.warp` never advanced.

---

## 2. Critical path

Ordered by dependency. Each item states what it unblocks, so the cost of slipping one is visible.

### 2.1 Contract completion — ▶

| | Item | Unblocks | Notes |
|---|---|---|---|
| ▶ | **Invariant suite** | deployment | `Σ paid ≤ Σ received`; no path loosens a bound; no rule ends neither executable nor cancellable; Trimmy never holds a balance across transactions |
| ○ | **Adversarial workflow against the implementation** | deployment | Now that code exists, attack the code — not the design. Prior red-teaming attacked a spec |
| ○ | **Deploy script** | everything on-chain | Immutable allowlists mean the constructor arguments *are* the security model; they get their own review |

### 2.2 On-chain reality — ○

| | Item | Unblocks | Settles |
|---|---|---|---|
| ○ | **Deploy + seed FXRP/testUSDT V3 pool** | every swap rule | **O-1** — `createPool` was never attempted; 80/80 `getPool` calls return zero |
| ○ | **Deploy Trimmy to Coston2** | keeper, front end, demo | — |
| ○ | **Measure `execute()` gas on Coston2** | fee model, refuse-to-arm threshold | **O-3** |
| ○ | **Sample `maxFeedAge` across separated windows** | production parameter | **O-2** — one calm window's p99 refuses to execute during exactly the stalls that matter |

We hold **96.88 C2FLR** and **13.15 FXRP** on `0x38d5…8E83`. The FXRP is enough to prove the
mechanism, thin for a realistic pool — more gets minted via FAssets from the XRPL testnet account.

### 2.3 The loop that makes it a product — ○

| | Item | Unblocks | Notes |
|---|---|---|---|
| ○ | **Keeper** | live demo | Permissionless executor. Must handle the revert-is-common case: near a threshold the price oscillates and reverts cost gas |
| ○ | **Plimsoll arming preflight** | safe arming | Dry-run every inner call of the 0xFE batch; refuse a payment that loses money |
| ○ | **Standalone `plimsoll decode` CLI** | the honesty story | Must be network-independent with a published `RuleParams` ABI. On stage, decode a batch we did not generate |
| ○ | **Arming front end** | real users | Xaman payload/deep-link. No install, no wallet-connect |
| ○ | **XRPL → arm end to end** | the demo | The whole point: one payment, no EVM wallet, no FLR |

### 2.4 Bounty 2 — ○

| | Item | Notes |
|---|---|---|
| ○ | Install Go 1.26.5 | Only bit-for-bit reproducible option; Python/TS embed host paths, so a rebuild changes the code hash and forces re-registration |
| ○ | Fix + upstream the three scaffold defects | `go.mod` pinned below the v0.0.22 minimum; `post-build.sh` missing `-command rRap`; `.toml.example` bind-mount failure. Real ecosystem contribution, and we need them fixed locally anyway |
| ○ | Build the private-trigger extension | `PRIVATE` trigger consumes a TEE-signed verdict |
| ○ | Register on Coston2, simulated first | Free. 254 of 268 active machines are `TEST_PLATFORM` and `getRandomTeeIds` routes to them |
| ○ | Signed on-chain heartbeat | Without it the enclave can censor silently and the front end cannot show *degraded* |
| ○ | **Real attestation window** | ~$19.81 for 240 continuous hours, or $0 if Flare devops host the image. **Cannot stop/start** — `tee-node` regenerates its identity key on boot |

### 2.5 Submission — ○

| | Item |
|---|---|
| ○ | Demo video — leads with the honest two-payment first run, not "one payment" |
| ○ | Two DoraHacks submissions, cross-referenced |
| ○ | README with reproduce-it-yourself commands, in the house style |
| ○ | Explicit statement of what pre-existed (SDK, Plimsoll) versus what was built during the program |

---

## 3. Decisions already made, recorded so they are not relitigated

- **Allowance-pull, not delegation.** `executeUserOp` is `onlyController`; there is no alternative.
- **Demo leads with TESTearnXRP**, not stXRP — stXRP's share price is exactly `1.000000` and a judge
  falsifies "live funded vault" in two `cast call`s.
- **Never say "stop-loss protection."** Say *"one-block conditional execution against the FTSO with an
  oracle-enforced floor, 1–3 seconds measured."*
- **Retire "a leaked keeper key does zero damage" as the headline.** True, but the wrong threat
  model — the front end and any anonymous observer both sit above the keeper. Publish the ranked
  adversary table instead.
- **`MAX_SLIPPAGE_BIPS = 50`.** The extractable band is linear in slippage. The residual — up to 50
  bips per execution, taken with certainty by any observer — is stated as a number, not denied.

---

## 4. Open questions, each tied to the step that settles it

| # | Question | Settled by |
|---|---|---|
| O-1 | Can a V3 FXRP pool be created and seeded on Coston2? | §2.2 pool deployment |
| O-2 | Production `maxFeedAge` | §2.2 multi-window sampling |
| O-3 | `execute()` gas, hence minimum viable `keeperFeeFlat` | §2.2 Coston2 measurement |
| O-4 | Does `AssetManager.redeem` accept a third-party redeemer with a user-specified XRPL destination? | Read verified AssetManagerFXRP source |
| O-5 | Do fee-only direct mints (`netMintAmountXrp: 0`) succeed or revert? | One Coston2 XRPL payment with a `0xFE` memo |
| O-6 | Does the arming batch admit a monotonically-safe guardian control plane? | Design + test after §2.3 |

---

## 5. Two things that are the user's call, not mine

1. **The Telegram post** asking whether Flare devops will host our image, and whether `TEST_PLATFORM`
   is acceptable for judging. Either answer is useful; one of them saves $19.81 and real operational
   risk.
2. **Whether to open the GCP account at all.** Not on the critical path — everything through §2.4's
   simulated registration is free. The decision only has to be made before the real attestation
   window, and the thing to check early is the **N2D quota**, because a non-billable Free Trial
   account is forbidden from requesting an increase.
