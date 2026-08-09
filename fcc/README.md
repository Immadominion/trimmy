# Trimmy Confidential Trigger — Flare Confidential Compute extension

**Bounty 2, and it exists because of a finding from Bounty 1.**

## The problem, measured rather than imagined

Trimmy's adversarial review produced finding **A2**: the execution floor is a *publicly computable
target price*. Every input to it — the FTSO reading, the rule's slippage, the amount — is on chain,
so an observer can compute the exact price at which a rule will fill, push the pool to precisely
that number in one atomic transaction, and take the whole slippage band with certainty. No keys
required. We could bound it (50 bips, arm-time depth cap, jitter) but not eliminate it: **any floor
is a target.**

The trigger has the same shape and it is worse. A rule armed as "sell 50,000 FXRP if XRP drops
below X" publishes X. Anyone can read `ruleAt(id).triggerValue` and knows the exact price at which a
large, price-insensitive sell arrives. The user is not merely exposed to slippage; they have
announced their stop to the people best placed to trade against it.

**This is the single most valuable thing to keep private in the entire product**, and it is not an
exotic requirement — it is the reason stop orders on centralised venues are not published.

## Why FDC cannot solve it

Flare's Data Connector is the natural first answer and it structurally cannot help. `Web2Json`'s
source identifier is literally **`PublicWeb2`**: the request, its URL and its headers are submitted
on chain and roughly a hundred independent providers each fetch it to reach consensus. That is what
makes it trustworthy, and it is exactly what makes it unable to hold a secret. An API key in a
header is a published API key. A threshold in a request body is a published threshold.

Confidentiality here is not a nicer version of FDC. It is a different guarantee, and a TEE is the
only place on Flare that can provide it.

## What this extension does

The threshold never appears on chain. The rule stores only a commitment.

```
arm            user commits  keccak256(threshold ‖ salt)  in the rule
provision      user sends the threshold to the enclave, ECIES-encrypted to its public key
evaluate       keeper asks the extension: "should rule N fire right now?"
               the enclave reads the price, compares against the secret it holds,
               and returns a SIGNED verdict — fire, or do not
execute        the contract verifies the TEE signature and the commitment, then runs
               the same floor, slippage and fee logic as any other rule
```

An observer sees a rule exists, that it is confidential, and — after the fact — that it fired. They
never see the number that made it fire.

## What this does NOT claim

Stated here because the submission will be read by someone looking for the gap:

- **A simulated TEE proves nothing about which code is running.** Its `codeHash` is a network-wide
  constant shared by 254 machines on Coston2. If this ships on `TEST_PLATFORM`, the "verify the code
  hash" step is decoration and is labelled as such. Real attestation means `GCP_AMD_SEV` and a
  measured hash.
- **The enclave operator can censor.** A confidential rule needs a fresh signed verdict; if we stop
  running the extension, those rules stop firing. That is a strictly weaker liveness property than
  the permissionless public rules, where anyone can execute. The two halves of the product have
  **different trust models** and the submission says so every time.
- **The threshold is private, not the outcome.** Once a rule fires, the trade is on chain like any
  other. This hides the trigger, not the history.

## Layout

```
scaffold/          upstream fce-extension-scaffold, unmodified, for reference
extension/         the Trimmy confidential-trigger extension
```

### Upstream scaffold defects — checked, and there is nothing to report

Another participant reported three defects in the hackathon Telegram. All three were verified
against current `main` (`ffb6c4c`, 2026-08-07) and **all three are already fixed upstream**:

| Reported | Status on current main |
|---|---|
| `go.mod` pins tee-node `v0.0.21`, below the `v0.0.22` minimum | **fixed** — both `go/go.mod` and `tools/go.mod` are at `v0.0.24` |
| `post-build.sh` calls `register-tee` without `-command rRap` | **fixed** — `REGISTER_TEE_COMMAND` defaults to `rRap` |
| missing `extension_proxy.coston2.docker.toml` fails with a confusing rootfs error | **fixed** — the file is gitignored by design, and `start-services.sh:316-319` now detects both the missing-file and the docker-created-directory cases and prints the exact `cp` command |

We had planned to upstream a PR for these and did not, because the work was already done. Recorded
here rather than silently dropped, so the claim "we contributed fixes" is never made on top of
somebody else's commit.

---

## The reference repositories are not vendored here

While building `extension/` we cloned four of Flare's own repositories to read and to measure
against. They are the Flare Foundation's code with their own history, so this repository ignores
them rather than vendoring them — that would bloat the clone and blur who wrote what. Nothing in
`extension/` depends on them at runtime; they were reference material and a source of measurements
recorded in [`UPSTREAM-FINDINGS.md`](UPSTREAM-FINDINGS.md).

To reproduce that reading environment:

```bash
cd fcc
git clone https://github.com/flare-foundation/fce-extension-scaffold.git
git clone https://github.com/flare-foundation/fce-sign.git
git clone https://github.com/flare-foundation/fce-weather-insurance.git
```

`extension/` began life as a copy of `fce-extension-scaffold` and is heavily modified; it **is**
ours and it is committed.
