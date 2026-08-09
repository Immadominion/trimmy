# TEE cost decision — "is this Google thing really that expensive?"

**Date:** 2026-08-06 · **For:** Trimmy / Flare Summer Signal, Bounty 2 · **Deadline:** 2026-08-14 19:59
**Synthesises:** `fcc-extension.md`, `gcp-confidential-space.md`, `keeper-security.md`, `rule-taxonomy.md`
(all in this directory), plus live price fetches I performed today.

Evidence labels: `[Verified]` primary source I read or a live read I performed · `[Measured]` arithmetic
from a cited price table · `[Inference]` reasoned, basis named · `[Unverified]` needs an experiment, and
the experiment is stated.

---

## 1. The direct answer

**No, it is not expensive. The ~$146/month number was arithmetically correct and framed wrong in three
separate ways at once. The honest figure for what Trimmy actually needs is $19.81 total — not per month,
total — with a credible path to $0.00 cash.**

Here is exactly where $146 came from and what is wrong with it. `[Measured]`

```
n2d-standard-4, AMD SEV, compute only, 720 h/month
  base machine                              $0.168984
  confidential premium, vCPU  4 × 0.005479  $0.021916
  confidential premium, mem  16 × 0.0007342 $0.0117472
                                            ──────────
                                            $0.2026472 /hr
  × 720 h  =  $145.91/month      ← the number you were quoted
  × 192 h  =  $ 38.91/8 days     ← the other number you were quoted
```

Three independent errors, each compounding:

1. **Wrong machine.** `n2d-standard-4` is 4 vCPU / 16 GiB. The workload is *one statically-linked
   `CGO_ENABLED=0` Go binary on a `gcr.io/distroless/static` base* — no runtime, no interpreter, no
   database. `[Verified — fce-sign/Dockerfile]` It serves three HTTP ports and polls a proxy. The
   correct machine is `n2d-highcpu-2` (2 vCPU / 2 GiB) at **$0.062376/hr**, a third of the base price.
   `[Verified — I fetched cloud.google.com/products/compute/pricing/general-purpose today, Iowa
   (us-central1) selected; the row reads verbatim `n2d-highcpu-2 | 2 | 2 GiB | $0.062376 / 1 hour`]`
2. **Wrong duration.** We are not renting a server for a month. We need a real enclave from the moment
   the pipeline works until judging is over. **240 hours**, not 720. And we need *zero* hours of it
   during development — the entire build is done free on the local/simulated path, and swapping to real
   hardware requires no code change. `[Verified — gcp-confidential-space.md §9.4: `MODE=0` on real
   Confidential Space "adds the hardware root of trust and nothing else functional"]`
3. **Wrong assumption that you pay cash at all.** A new Google Cloud account carries **$300 of Welcome
   credit valid for 90 days**, and Confidential VMs are *not* on the exclusion list. `[Verified — I
   fetched cloud.google.com/free/docs/free-cloud-features today; the exclusions are GPUs, Marketplace,
   quota increases, Windows Server images, and VMware Engine]` $300 covers this fifteen times over.

**The honest number: $19.81 of compute, drawn against $300 of free credit, so $0.00 out of pocket —
falling back to $19.81 cash if the credit turns out to be unavailable to you.**

One thing that got *worse*, not better, on close reading, and you need to know it: **you cannot save
money by stopping the VM overnight.** `tee-node` "generates a fresh ECDSA key pair on each boot, which
serves as its identity (`teeID`)". `[Verified — flare-foundation/tee-node, docs/concepts.md, quoted in
gcp-confidential-space.md §5.4]` Every stop/start destroys the on-chain registration and forces a full
`register → fresh attestation → FTDC availability check → promote` cycle. Budget **continuous** hours.
This directly contradicts scenario (c) in `gcp-confidential-space.md §5.2` — see §5 below.

---

## 2. Ranked cost table

Run window used throughout: **240 hours** = 2026-08-12 08:00 UTC → 2026-08-22 08:00 UTC. That is 2.5
days of soak before the deadline and 7.5 days of tail for judges to look. Judges look *after* the
deadline; a TEE that is dead at judging time scores zero, so the tail is not padding.

All prices us-central1 (Iowa), fetched by me today unless noted. The AMD SEV confidential premium table
**has no region selector**, so it is region-independent; only the base machine price moves by region.
`[Verified — I read the entire cloud.google.com/confidential-computing/confidential-vm/pricing page
today; region selectors appear only on the GPU and Hyperdisk tables]`

| # | Option | Total, 240 h | Per month (730 h) | Real attestation? | FTDC accepts? |
|---|---|---:|---:|---|---|
| 1 | **Flare devops hosts your image** (§4) | **$0.00** | $0.00 | **YES** — their machines report `GCP_AMD_SEV` | **Yes** |
| 2 | **`n2d-highcpu-2` SEV on $300 free credit** | **$0.00 cash** ($19.81 credit) | $60.26 | **YES** | **Yes** |
| 3 | `n2d-highcpu-2` SEV, cash | **$19.81** | $60.26 | **YES** | **Yes** |
| 4 | `n2d-standard-2` SEV, cash *(safe fallback)* | $26.18 | $79.62 | **YES** | **Yes** |
| 5 | `n2d-highcpu-2` + `e2-small` proxy VM | $25.69 | $78.14 | **YES** | **Yes** |
| 6 | `n2d-standard-2` SEV, 192 h only (8 days) | $20.94 | — | **YES** | Yes, until it stops |
| 7 | `n2d-standard-2` SEV on **Spot** | $8.66 | $26.34 | YES *while alive* | Yes, until preempted |
| 8 | `n2d-highcpu-2` **SEV-SNP** instead of SEV | $18.32 | $55.74 | **UNKNOWN** | **Unknown** |
| 9 | Intel TDX, `c3-standard-4` | unpriced | — | YES | Yes (7 live machines) |
| 10 | **Simulated TEE** (`MODE=1`), local + free tunnel | **$0.00** | $0.00 | **NO** | **Yes, today** — see §5 |
| 11 | AWS Nitro / Azure ACC / Phala / Oasis / bare-metal SEV | n/a | n/a | **NO** | **No** |
| 12 | *The original estimate:* `n2d-standard-4` 24/7 | $50.49 all-in | $153.58 | YES | Yes |

### Arithmetic, shown

**Verified unit prices** `[Verified — all four fetched by me 2026-08-06]`:

| Item | Price | Source |
|---|---|---|
| AMD SEV premium, vCPU | $0.005479 / vCPU-hr | confidential-vm/pricing, verbatim |
| AMD SEV premium, memory | $0.0007342 / GiB-hr | confidential-vm/pricing, verbatim |
| AMD SEV-SNP premium, vCPU / mem | $0.0027502 / $0.0003686 | same page |
| Intel TDX premium, vCPU / mem | $0.0033982 / $0.0004555 | same page |
| AMD SEV Spot premium, vCPU / mem | $0.0012822 / $0.0001712 | same page |
| `n2d-highcpu-2` (2 vCPU, 2 GiB) | $0.062376 /hr | general-purpose pricing, verbatim |
| `n2d-standard-2` (2 vCPU, 8 GiB) | $0.084492 /hr | same |
| `n2d-standard-4` (4 vCPU, 16 GiB) | $0.168984 /hr | same |
| `e2-small` (2 vCPU, 2 GiB) | $0.016752855 /hr | same |
| `n2d-standard-2` Spot | $0.026912 /hr | spot-vms/pricing `[Verified — gcp doc §5.1]` |
| Balanced PD provisioned space | $0.000136986 /GiB-hr | disks-image-pricing `[Verified — gcp doc §5.1]` |
| Ephemeral external IPv4, in use, standard VM | $0.005 /hr | vpc/network-pricing `[Verified — gcp doc §5.1]` |
| Ephemeral external IPv4, in use, Spot VM | $0.0025 /hr | same |
| VM↔VM same zone, internal IP | $0.00 | same |
| Internet egress → North America, Premium | $0.12 /GiB, first 1 GiB/month free | same |

**Option 3 — `n2d-highcpu-2`, AMD SEV, 20 GiB pd-balanced, ephemeral external IP** `[Measured]`:

```
base machine                                  $0.0623760
confidential premium, vCPU   2 × 0.005479     $0.0109580
confidential premium, mem    2 × 0.0007342    $0.0014684
boot disk                   20 × 0.000136986  $0.0027397
ephemeral external IPv4                       $0.0050000
                                              ──────────
                                      TOTAL   $0.0825421 / hour

× 240 h  =  $19.81      × 192 h  =  $15.85      × 730 h  =  $60.26/month
```

**Option 4 — `n2d-standard-2`, same otherwise** `[Measured]`:

```
0.084492 + 0.010958 + (8 × 0.0007342 = 0.0058736) + 0.0027397 + 0.005 = $0.1090633 / hour
× 240 h  =  $26.18      × 192 h  =  $20.94      × 730 h  =  $79.62/month
```

The delta between options 3 and 4 is **$6.37 over the run window** — 6 GiB of memory you will not use,
priced twice (once in the base machine, once in the confidential premium).

**Option 5 — add the second machine.** Confidential Space runs *exactly one* container per VM
("Confidential Space runs the container launcher, which in turn launches a single container")
`[Verified — docs.cloud.google.com/confidential-computing/confidential-space/docs/create-customize-workloads,
quoted in gcp doc §3]`, so `ext-proxy` and `redis` must live somewhere else. `[Measured]`

```
e2-small 0.016752855 + disk 0.0027397 + IP 0.005 = $0.0244926 /hr  × 240 h = $5.88
```

You can skip this entirely by running `ext-proxy` + `redis` on your own laptop behind a **free named
Cloudflare tunnel**, which is what `.env.local.coston2` does and what most live Coston2 machines do.
`[Verified — gcp doc §5.3]` Put the tunnel on a *named* Cloudflare tunnel or a reserved ngrok domain,
not a random `trycloudflare.com` URL — the URL is written on-chain as the machine's `url` and a rotating
URL means a dead machine row. `[Verified — fcc-extension.md §4.4]`

**Option 7 — Spot** `[Measured]`: `0.026912 + 0.0025644 + 0.0013696 + 0.0027397 + 0.0025 = $0.0360857/hr
× 240 = $8.66`. **Do not.** Preemption → reboot → *new* `teeID` → the on-chain record no longer matches
→ full re-registration, and the promote step is gated on an FTDC proof you can only obtain after a fresh
availability check. `[Verified — fce-extension-scaffold/tools/pkg/fccutils/registration.go, quoted in gcp
doc §5.4]` Saving $11 in exchange for a coin-flip on whether your TEE is registered when judges look is a
bad trade at any budget.

**Option 8 — SEV-SNP** `[Measured]`: premium is roughly half SEV's, saving
`2×(0.005479−0.0027502) + 2×(0.0007342−0.0003686) = 0.0054576 + 0.0007312 = $0.0061888/hr`, i.e.
`$0.0763533/hr` all-in, `× 240 h = $18.32` — a saving of **$1.49**. **Not worth it.** Flare's tooling hardcodes
four legal platform values — `GCP_INTEL_TDX`, `GCP_AMD_SEV`, `GCP_AMD_SEV_ES`, `TEST_PLATFORM`
`[Verified — fce-extension-scaffold/tools/pkg/fccutils/encoding.go:11-16, quoted in gcp doc §3.1]` —
and SEV-SNP is not among them. SEV-SNP is also zone-restricted. $1.50 does not buy an unknown.

**Option 11 — non-GCP.** Not a cost question, an impossibility question. `tee-node`'s production
attestation path POSTs to `/v1/token` on the Unix socket `/run/container_launcher/teeserver.sock`, parses
a **Google** JWT, derives `platform` from the `hwmodel` claim and `codeHash` from
`submods.container.image_id`. `[Verified — tee-node/docs/attestation.md, confirmed by value-level match
against Flare's live production JWT, gcp doc §3.1]` AWS Nitro and Azure produce entirely different
attestation formats and there is no abstraction layer to swap. Using them means forking `tee-node`. That
is not a cheaper path; it is a different project.

---

## 3. The recommendation

**Do this. Total: $19.81, drawn against $300 of free Google credit, so realistically $0.00 cash.**

**Today (2026-08-06), in this order:**

1. **Send the two messages in §4.** They are free options with a multi-day lead time; send them before
   you need them, not after. Five minutes of work.
2. **Sign up for Google Cloud and claim the $300 credit.** *Immediately upgrade the billing account to
   Paid.* You keep the unused credit, and you regain the ability to file a quota increase — which a
   non-billable Free Trial account is explicitly **forbidden** from doing. `[Verified — free-cloud-features,
   exclusion list read today]` This is the single most common way this plan dies.
3. **Check quota before anything else.** 60 seconds:
   ```bash
   gcloud services enable compute.googleapis.com --project="$PROJECT_ID"
   gcloud compute regions describe us-central1 --project="$PROJECT_ID" \
     --format="table(quotas.metric,quotas.limit,quotas.usage)" \
     | grep -Ei 'N2D_CPUS|^CPUS|IN_USE_ADDRESSES'
   ```
   You need `N2D_CPUS >= 2` and `CPUS >= 2`. If either is 0, that is the blocker — not money.
4. **Set a $50 budget alert.** IAM will not stop spend; a budget alert is the only guard.
   ```bash
   gcloud billing budgets create --billing-account="$BILLING_ACCOUNT_ID" \
     --display-name="trimmy-tee cap" --budget-amount=50USD \
     --threshold-rule=percent=0.5 --threshold-rule=percent=0.9 --threshold-rule=percent=1.0
   ```

**2026-08-06 → 2026-08-11: build entirely on the free simulated path.** `SIMULATED_TEE=true` +
`LOCAL_MODE=false` against real Coston2, `ext-proxy` + `redis` local behind a named tunnel. Cost $0.00.
Work through `fcc-extension.md §5.8` steps 1-5. Real Confidential Space adds the hardware root of trust
and **nothing else functional** `[Verified — gcp doc §9.4]`, so every hour the real VM runs before your
handler works is money burned for no information.

**2026-08-11: run the machine-type experiment.** Create one `n2d-highcpu-2` Confidential VM. It either
boots and `/info` reports `platform` starting `0x4743505f414d445f534556`, or it does not. Cost of finding
out: **$0.09** for one hour. If it fails, change one flag to `n2d-standard-2` and pay $26.18 instead.

**2026-08-12 08:00 UTC: bring the real TEE up and leave it up.** Exact command, adapted from
`gcp-confidential-space.md §7.1` with the machine type corrected:

```bash
gcloud compute instances create trimmy-tee-1 \
    --project="$PROJECT_ID" --zone=us-central1-a \
    --machine-type=n2d-highcpu-2 \
    --confidential-compute-type=SEV \
    --maintenance-policy=MIGRATE \
    --shielded-secure-boot \
    --image-project=confidential-space-images \
    --image-family=confidential-space-debug \
    --boot-disk-size=20GB --boot-disk-type=pd-balanced \
    --service-account="$SA_EMAIL" --scopes=cloud-platform \
    --metadata="^~^\
tee-image-reference=us-central1-docker.pkg.dev/${PROJECT_ID}/${REPO}/trimmy-extension:v0.1.0~\
tee-container-log-redirect=cloud_logging~\
tee-restart-policy=Always~\
tee-monitoring-memory-enable=true~\
tee-env-MODE=0~\
tee-env-EXTENSION_ID=0x...~\
tee-env-INITIAL_OWNER=0x...~\
tee-env-CHAIN_URL=https://coston2-api.flare.network/ext/C/rpc~\
tee-env-PROXY_URL=http://<proxy-host>:6663~\
tee-env-LOG_LEVEL=INFO"
```

Then register once, verify, and **do not stop it** until 2026-08-22.

Non-obvious things that will cost you money or a day if you skip them, all verified in the source docs:

- **`--maintenance-policy=MIGRATE`.** Live migration is supported *only* on N2D with AMD SEV on Milan.
  `[Verified — supported-configurations, read today: "Live migration is only supported on N2D machine
  types with AMD EPYC Milan CPU platforms running AMD SEV"]` Without it, a host maintenance event
  terminates the VM, which destroys the `teeID`, which un-registers you. This is *the* reason to stay on
  N2D+SEV rather than chasing a cheaper premium.
- **Use an ephemeral IP, never a static one.** A reserved-but-unused static IP bills $0.01/hr — *double*
  the in-use rate. `[Verified — vpc/network-pricing]`
- **`confidential-space-debug`, not the production image.** Flare's own live Coston2 machine runs debug
  (`dbgstat: "enabled"` in their production JWT) `[Verified — gcp doc §3]`, it is accepted by FTDC, and
  it gives you SSH. The production image permanently disables SSH — nobody, including you, gets a shell.
- **Put the proxy in the same zone** if you use a proxy VM. Same-zone internal VM↔VM traffic is $0.00.
- **Pin `SOURCE_DATE_EPOCH`.** `codeHash` *is* the container image ID — not the registry digest, not a VM
  measurement. `[Verified — value-level match against Flare's live JWT, gcp doc §3.1]` A non-reproducible
  build changes the hash, which forces re-running `allow-tee-version` *and* re-registering.
- **If Trimmy needs `CHAIN_ID` or `GOVERNANCE_*` overridable at launch, add them to
  `tee.launch_policy.allow_env_override` in the Dockerfile now.** The shipped extension label omits both
  even though `docker-compose.yaml` sets them, so the compose path and the Confidential Space path differ
  here. `[Verified — gcp doc §7.1]` Changing the label changes the `codeHash`, so do it *before* you
  whitelist, not after.
- **Never reuse `fce-sign/.env.coston2`'s committed private key** (`1f467319d0…`). It is in a public
  Flare repo and anyone can spend from and impersonate it. `[Verified — gcp doc §10.11]`

**Why not the free simulated path, given it costs $0.00 and 254 of 268 live Coston2 machines use it?**
Because it silently guts the product. Trimmy's credential protocol has, as step 2, *"verify `codeHash`
on-chain — `TeeExtensionRegistry` says this hash is whitelisted for extension `EXTENSION_ID`. Verify the
reproducible build matches our published source. ONLY THEN proceed."* `[Verified — fcc-extension.md §5.3]`
Under `SIMULATED_TEE=true`, `codeHash` is the constant `0x194844cf417dde867073e5ab7199fa4d21fd82b5dbe2bdea8b3d7fc18d10fdc2`,
**identical on every simulated machine on the network**. `[Verified — gcp doc §2.1, 254 live examples]`
Step 2 becomes theatre. The user is no longer trusting a code hash; they are trusting you. That is
precisely the quality reduction you have refused, and it is the reduction Bounty 2 is *about*. It also
collapses the strongest argument in `keeper-security.md` — that a TEE-evaluated trigger is the honest
answer to threat T8, information leakage. `[Verified — keeper-security.md §T8]` For $19.81, do not do
this to your own product.

**Keep the simulated path anyway, as a labelled hot standby.** It costs nothing, it is your rollback if
GCP quota bites on 2026-08-12, and re-running it is a `docker compose up` away.

---

## 4. Free things to ask for, and the exact messages

### 4.1 Flare devops hosting the VM — the best free option, ask today

This is not a favour you are inventing; it is the **documented primary path**. `fce-sign`'s deployment
doc has a "Devops responsibilities" section that reads *"Devops deploys the image on a GCP Confidential
Space VM with: `MODE`=0 … `ext-proxy` container with the right chain TOML … Public HTTPS URL routed to
port 6664 of the proxy"*, and names **Aljaž Konečnik** as the devops contact for that repo.
`[Verified — fce-sign/TESTNET_DEPLOYMENT.md lines 394-409, quoted in gcp doc §4.1]`

One clarification so the ask lands correctly: **Flare's existing machines cannot be borrowed.**
`tee-proxy-coston2-1`, `-2` and `-transfers` are real `GCP_AMD_SEV` Confidential Space VMs
`[Verified — live JWT decode, gcp doc §3]`, but the machine registry is keyed per-extension —
`getRandomTeeIds(extensionId, count)` selects only machines registered against *that* extension
`[Verified — gcp doc §2.1]`. So there is no shared pool to join. The ask is for devops to run **your**
image on **their** infrastructure. `[Inference — from the extensionId-keyed selection function]`

**Send this, today, in the Summer Signal hackathon channel (Telegram/Discord), and to Flare DevRel:**

> **Subject: Summer Signal Bounty 2 — is the devops Confidential Space hand-off open to participants?**
>
> Hi — I'm building Trimmy, a Bounty 2 (Confidential Compute Apps) entry. It's an FCC TEE extension that
> evaluates a private trigger over a user's own read-only exchange API key *inside* the enclave, so the
> credential, the balance and the threshold never touch the chain. The credential arrives via
> `POST /direct` on the proxy's external port, never as calldata.
>
> `fce-sign/TESTNET_DEPLOYMENT.md` documents a devops hand-off — *"Devops deploys the image on a GCP
> Confidential Space VM"* — and names Aljaž Konečnik as the devops contact. Two questions:
>
> 1. **Is that hand-off available to hackathon participants on Coston2, or is it internal-only?** If it
> is available, what's the lead time and what do you need from me? I can have the reproducible image,
> `EXTENSION_ID`, `INITIAL_OWNER` and the `tee.launch_policy.allow_env_override` label ready today, and I
> can be flexible on timing as long as the machine is live and registered before 2026-08-14 19:59 and
> stays up through judging.
> 2. **If it isn't, is there a Flare or sponsor cloud-credit pool for participants who need a real
> Confidential Space VM?** I've costed it precisely: `n2d-highcpu-2` with AMD SEV for the judging window
> is about **$20**. Small, but it's the only line item in the project that isn't free, and I'm
> self-funding from Nigeria.
>
> For context, I've verified on-chain that 254 of the 268 currently-active Coston2 TEE machines are
> `TEST_PLATFORM`, so the simulated path clearly works today. I'd rather ship the real thing — Bounty 2
> is *about* the attestation, and a submission whose `codeHash` is the shared simulated sentinel can't
> honestly claim it.
>
> Thanks — happy to share the full deployment write-up either way.

Why this is likely to work: it demonstrates you have already done the work, asks a precise question,
names a small number, and gives them an easy yes. `[Inference]`

### 4.2 Hackathon sponsor credits — ask in the same breath

`[Unverified]` — I have no primary source on whether Summer Signal has a credit pool. **Experiment: ask.
It costs one message.** Post separately in the general channel so it is visible to organisers, not buried
in a devops thread:

> Quick ask for organisers/sponsors: **is there a cloud-credit pool for Summer Signal participants?**
> Bounty 2 (Confidential Compute) needs a GCP Confidential Space VM for real AMD SEV attestation —
> there's no non-GCP path, because `tee-node`'s attestation is hard-wired to the Confidential Space
> socket and a Google JWT. I've costed it at **~$20 for the judging window** (`n2d-highcpu-2`, AMD SEV,
> 240 h), so it's a small ask, but it's the one thing in the project that isn't free and several of us
> are self-funding. Happy to share the full breakdown if it's useful to other teams.

### 4.3 Google Cloud $300 Welcome credit — no asking required

`[Verified — cloud.google.com/free/docs/free-cloud-features, fetched today]`

> "The Free Trial gets you a **$300 Welcome credit to spend over 90 days**… Signing up for the Free
> Trial creates a Free Trial billing account that is preloaded with $300 in free Welcome credit."

Eligibility, verbatim: *"You've never been a paying user of Google Cloud, Google Maps Platform, or
Firebase"* **and** *"You haven't previously signed up for the Free Trial."*

$300 ÷ $19.81 = **15 run-windows**. `[Measured]` The credit is not the constraint; eligibility is.

Two frictions specific to your situation, both real:

- **A payment method must verify.** *"you must provide a credit card or other payment method that is
  valid for the period of the Free Trial. Depending on your country, you might also need to verify your
  bank account."* Google places a temporary hold "between $0.00 and $1.00 USD". `[Verified — same page]`
  `[Unverified]` whether a Nigerian card verifies. **Experiment: attempt the signup. Ten minutes, and it
  either works or it doesn't.** Do this today, not on the 12th.
- **The quota trap.** *"While your billing account is a non-billable Free trial account, you can't…
  Request a quota increase."* `[Verified — same page, verbatim]` So: claim the credit, then upgrade to
  Paid immediately. *"Although upgrading to a Paid billing account ends your Free Trial, you keep any
  unused credit until it expires 90 days from the Free Trial signup."* `[Verified — same page]` You lose
  nothing and you regain the ability to unblock yourself.

### 4.4 Google for Startups Cloud Program

`[Unverified]` — I attempted `cloud.google.com/startup` and the page truncated before the tier table, the
same failure `rule-taxonomy.md` hit. I will not quote numbers I have not read. **Experiment: open
cloud.google.com/startup in a browser and read the current Start-tier amount and eligibility.** My
honest read is that this is **not a hackathon-window play** — startup-program approvals run days to
weeks, and you need the machine in six days. Apply if you want it for the *product* phase; do not make
the submission depend on it. `[Inference — from typical program lead times, not from a source I read]`

---

## 5. Contradictions between the four investigations, resolved

### C1 — "FTDC rejects simulated TEEs" (Flare's docs, and your brief) vs. 254 live `TEST_PLATFORM` machines

`fce-sign/TESTNET_DEPLOYMENT.md` says it twice, unambiguously: *"FTDC rejects simulated TEEs"* and
*"Flare's Coston/Coston2 FTDC rejects `TEST_PLATFORM` / hardcoded simulated codeHash. Deploy on a real
Confidential Space VM."* `[Verified — quoted in gcp doc §2.3]` Your brief repeats it. The
`gcp-confidential-space` investigation enumerated the live registry and found **254 of 268 active Coston2
TEE machines are `TEST_PLATFORM`**, several behind `ngrok-free.dev` and `trycloudflare.com` URLs, one
returned by `getRandomTeeIds` — the actual selection function — and one `GCP_INTEL_TDX` machine promoted
on 2026-08-04, *during* this hackathon. `[Verified — live chain reads, gcp doc §2.1]`

**Resolution: I trust the chain, and so should you, but only about the present tense.** A live read of
`getAllActiveTeeMachines` on deployed bytecode is ground truth about what the system does *right now*; a
markdown file is a claim about what it did when someone wrote it. The `gcp-confidential-space`
investigation is additionally credible here because it *self-corrected* — an earlier pass concluded the
opposite from the docs and the author threw it out after reading the chain. That is the correct direction
of update.

But note what this does and does not license. It licenses "simulated works today". It does not license
"simulated will work on 2026-08-14", and it certainly does not license "simulated is as good". The most
probable explanation is that Coston2 FTDC policy was relaxed for the hackathon `[Inference — from 254
tunnel-hosted registrations clustered in July/August]`, which means it can tighten back with no notice,
plausibly right after the hackathon and therefore *during judging*. **Your brief was directionally right
for the wrong reason: don't build on simulated, but the reason is product quality and policy risk, not a
hard rejection that demonstrably isn't happening.**

### C2 — `gcp-confidential-space.md` §5.2 contradicts `gcp-confidential-space.md` §5.4

§5.2 offers scenario (c), *"30 days, stopped outside working hours — $25.36"*, as a legitimate saving.
§5.4 of the same document quotes `tee-node/docs/concepts.md`: *"It generates a fresh ECDSA key pair on
each boot, which serves as its identity (`teeID`)."*

**Resolution: §5.4 wins; scenario (c) is invalid after registration and should not be in any budget.**
§5.4 quotes primary source; §5.2 is a spreadsheet exercise that did not account for it. Every stop/start
yields a new `teeID`, an on-chain record that no longer matches, and a mandatory
`register → attestation → FTDC availability check → promote` cycle whose promote step is gated on a proof
obtainable only *after* a fresh availability check. `[Verified — registration.go, gcp doc §5.4]` Worse,
`fcc-extension.md §3.3` documents that the scaffold ships `register-tee` **without** `-command rRap`, so
the resume path reuses a stale one-shot challenge and dies with `Verification.ChallengeExpired`.

Scenario (c) is valid for exactly one window: **before** you register, while you are iterating on the
image. After registration, budget continuous hours. This is why §2's table prices 240 continuous hours
and not a duty cycle.

### C3 — `rule-taxonomy.md` §5.1 leaves the GCP price `[Unverified]` and calls it "a fixed monthly cost"

`rule-taxonomy.md` records: *"Both attempts at cloud.google.com's confidential-VM pricing page returned
404 or truncated content"*, and frames the TEE as *"a fixed monthly cost, not a marginal one"*.

**Resolution: `gcp-confidential-space.md` wins on the number; `rule-taxonomy.md` wins on the framing —
but only for the product, not for the hackathon.** The gcp doc extracted the figures from the page's
static HTML, and **I independently re-fetched both pages today and got byte-identical figures**, so the
prices are now doubly verified. `rule-taxonomy`'s "fixed monthly" framing is almost certainly the origin
of the $146/month anchor that alarmed you: it is the right mental model for *Trimmy the product*, and the
wrong one for *Trimmy the hackathon submission*, which needs 240 hours, not a subscription. For the
record, the post-hackathon product floor is **$60.26/month** (`n2d-highcpu-2`) or **$78.14/month** with a
dedicated proxy VM `[Measured]` — not $146, because that assumed a machine twice the required size.

### C4 — `gcp-confidential-space.md` §8.3 recommends simulated; `fcc-extension.md` §5.3 requires real

The gcp doc's §8.3 and recommendation #1 say build on simulated, GCP is off the critical path. The
fcc-extension doc's credential protocol makes the *entire* trust argument rest on the user verifying a
real, whitelisted, reproducible `codeHash` before handing over an exchange API key.

**Resolution: `fcc-extension.md` wins, and this is the most consequential call in this document.** The
gcp doc is optimising for "can I register a machine cheaply", and its answer is correct. The fcc doc is
optimising for "is the product I am shipping actually the product I am describing", and under
`SIMULATED_TEE=true` the answer is no — `codeHash` is a network-wide constant that proves nothing about
which code is running, so step 2 of the credential protocol is decoration. `keeper-security.md` §T8
independently reaches the same place: the TEE is the answer to information leakage *only if it is a TEE*.
Two of the four investigations need real attestation for the product to be what it claims; one is costing
infrastructure. Given that you have refused quality reductions, and given that the disagreement is worth
**$19.81**, this is not a close call.

The gcp doc's §9.3 framing is still exactly right for the *submission text* — be explicit and precise
about what is and isn't guaranteed. You will just be writing it about a real enclave.

### C5 — `gcp-confidential-space.md` §4.3 says `n2d-standard-2` is the floor. It isn't.

The doc justifies `n2d-standard-2` partly as *"the smallest N2D standard type, so this is the floor
rather than a sizing decision"*. That is true of the *standard family* and false of the *N2D series*.
`n2d-highcpu-2` is 2 vCPU / 2 GiB at **$0.062376/hr** vs `n2d-standard-2` at $0.084492/hr, and it also
carries 6 fewer GiB of confidential-memory premium. `[Verified — I fetched the N2D high-CPU table today;
row reads verbatim `n2d-highcpu-2 | 2 | 2 GiB | $0.062376 / 1 hour`, Iowa (us-central1)]`

**Resolution: this is a new finding, not a contradiction — the earlier investigation simply did not look
at the high-CPU table.** It is worth **$6.37** over the run window and **$19.36/month** thereafter, and
the AMD SEV premium applies to the whole N2D series, not to specific types `[Verified — confidential-vm
pricing: "applies to AMD SEV VM instances on the N2D, C2D, C3D, and C4D machine series"]`. The residual
risk is that 2 GiB might be too little for the Confidential Space container launcher — see §6.

### C6 — Your brief says `MODE=1` "produces simulated attestation which FTDC rejects"

Half right. What `SIMULATED_TEE=true` actually does is make the *client-side tool* skip JWT parsing and
substitute two hardcoded constants; it skips **no** on-chain step — `allow-tee-version`,
`set-governance` and the full `rRap` registration including a real FTDC availability check all still run.
`[Verified — fccutils/common.go read verbatim, gcp doc §9.2]` And empirically they succeed (C1). The
accurate statement for your submission is: *"`MODE=1` substitutes a constant code hash for a measured
one. Coston2's FTDC currently accepts it — 254 of 268 live machines are exactly that — but it proves
nothing about which code is executing, so Trimmy ships `MODE=0` on real AMD SEV."*

---

## 6. What remains unverified, and the experiment that settles each

| # | Unverified | Experiment | Cost of experiment | What it changes | Priority |
|---|---|---|---|---|---|
| U1 | Does `n2d-highcpu-2` accept `--confidential-compute-type=SEV`, and is 2 GiB enough for the Confidential Space launcher + your image? Google documents SEV at **series** level ("N2D"), not type level, and their own examples all use `n2d-standard-2`. | Create one. Wait for boot. `curl "$EXT_PROXY_URL/info" \| jq '.machineData.platform'` and confirm it starts `0x4743505f414d445f534556`. | **$0.09** (1 hour) | $19.81 → $26.18 if it fails. One flag change. | **High — run it 2026-08-11** |
| U2 | Are you eligible for the $300 credit (never a paying GCP/Maps/Firebase user, never previously signed up), and will a Nigerian payment method verify? | Attempt signup at console.cloud.google.com. Look for the $300 banner; watch for the $0–$1 authorization hold to clear. | 10 minutes | $0.00 cash → $19.81 cash | **High — run it today** |
| U3 | Default `N2D_CPUS` / `CPUS` quota in a brand-new project. Google explicitly does not publish it: *"Not all projects have the same quotas."* | `gcloud compute regions describe us-central1 --format="table(quotas.metric,quotas.limit,quotas.usage)"` — need ≥2 of each. | 60 seconds | If 0, and you're still on a Free Trial account, you **cannot** file an increase. This kills the plan, not the budget. | **High — run it today** |
| U4 | Will Flare devops host a participant's extension, and with what lead time? | Send the §4.1 message. | 5 minutes | $19.81 → $0.00 | **High — send today** |
| U5 | Is there a Summer Signal sponsor credit pool? | Send the §4.2 message. | 2 minutes | $19.81 → $0.00 | Medium |
| U6 | Will Coston2 FTDC still accept `TEST_PLATFORM` on 2026-08-14 and through judging? | Re-run the §2.1 census from `gcp-confidential-space.md` (3-minute script) on 08-14 and again on 08-18. | free | Only matters if you fall back to simulated. Keep the output as submission evidence either way. | Medium |
| U7 | Can the workload reach `api.kraken.com` from inside a real Confidential Space VM? Egress policy/NAT on our VM is untested. `fce-weather-insurance` calls OpenWeatherMap so egress works in principle. | Deploy, then curl the exchange endpoint from inside the workload and read the result via `tee-container-log-redirect=cloud_logging`. | included in U1 | **This is a product-blocker, not a cost item.** If egress fails, the extension cannot evaluate anything. Test it on 08-11, not 08-13. | **High** |
| U8 | Is there any billed SKU for Confidential Space or the attestation service beyond the CVM premium? | Largely closed: I read the **entire** Confidential VM pricing page today and there is no Confidential Space line item and no attestation SKU — only the flat per-vCPU/per-GiB premium, GPU confidential pricing, Hyperdisk confidential mode, and Confidential GKE. Residual: run 24 h and read the billing export grouped by SKU for `confidentialcomputing.googleapis.com`. | free | Would add an unknown to every figure above. Low likelihood. | Low |
| U9 | Google for Startups Cloud Program tiers, amounts, eligibility, lead time. | Open cloud.google.com/startup in a browser (it truncates for automated fetches). | 5 minutes | Irrelevant to the 8-day window; relevant to the product phase. | Low |
| U10 | Default boot disk size of the `confidential-space-debug` image — I modelled 20 GiB by choice, not from a requirement. | `gcloud compute images describe-from-family confidential-space-debug --project=confidential-space-images --format='value(diskSizeGb)'` | 10 seconds | 10 GiB instead of 20 saves $0.33 over 240 h. Not worth chasing. | Low |
| U11 | Exact egress volume from the TEE (Coston2 RPC polling + exchange API). Modelled as under the 1 GiB/month free tier. | Read the billing export after 24 h. | free | 5 GiB/month = $0.48. Even 20 GiB = $2.28. Cannot move the decision. | Low |

---

## 7. One-paragraph version, for when you're deciding at 2am

The $146 figure was for a machine twice the size you need, running for a month you don't need, paid for
with money you probably won't spend. The real number is **$19.81** for 240 continuous hours of a
2-vCPU/2-GiB `n2d-highcpu-2` with AMD SEV — enough to be registered, attested, and live from two days
before the deadline through a week of judging — and a new Google Cloud account comes with **$300** of
credit that covers it fifteen times, so the expected cash cost is **$0.00**. Ask Flare devops to host it
(free, documented, send the message today) and ask about sponsor credits in the same hour; if either
lands, you pay nothing and you didn't need the credit. Build everything on the free simulated path until
2026-08-11 — the real VM adds the hardware root of trust and *nothing else functional*, so running it
sooner buys you nothing. There is no cheaper path that keeps real attestation: non-GCP TEEs are not a
cost decision but an impossibility, because `tee-node` parses a Google JWT off a Confidential Space Unix
socket and has no abstraction layer. And do not save money by switching it off overnight or running Spot
— the node mints a fresh identity keypair on every boot, so every restart un-registers you. The one thing
worth double-checking before you commit is whether `n2d-highcpu-2` is accepted for SEV; that experiment
costs nine cents and the fallback costs $6.37 more.

---

*All live price fetches performed 2026-08-06 against `cloud.google.com/products/compute/pricing/general-purpose`
(Iowa/us-central1 selected), `cloud.google.com/confidential-computing/confidential-vm/pricing`,
`cloud.google.com/free/docs/free-cloud-features`, and
`docs.cloud.google.com/confidential-computing/confidential-vm/docs/supported-configurations`. Flare
repository and live-chain claims are inherited from `fcc-extension.md` and `gcp-confidential-space.md`
with the source location named at each point of use.*
