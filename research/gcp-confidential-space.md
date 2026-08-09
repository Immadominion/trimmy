# GCP Confidential Space for a Flare FCC TEE node — provisioning, true cost, access hand-off, and whether you need it at all

**Date:** 2026-08-06 · **For:** Trimmy / Flare "Summer Signal" (deadline 2026-08-14 19:59)

Evidence labels: `[Verified]` primary source / live chain / code actually read · `[Measured]` computed from a
cited price table · `[Inference]` reasoned from verified facts, source named · `[Unverified]` needs an
experiment, and the experiment is stated.

> **Revision note.** An earlier pass of this document concluded, on the strength of Flare's own written
> documentation, that a simulated TEE could not complete registration on Coston2 and that a real GCP
> Confidential Space VM was therefore probably required. **That conclusion was wrong.** I subsequently read
> the live Coston2 `FlareTeeManager` contract directly and found the opposite. Section 2 is the correction and
> is the most important part of this document. Everything about GCP cost and provisioning remains accurate,
> but it is now a contingency plan, not the critical path.

---

## 1. Headline

**Trimmy does not need a GCP account, a Confidential Space VM, or a single dollar of cloud spend to run a real
Flare Confidential Compute extension on Coston2.**

I proved this by census rather than by reading docs. Of the **268 TEE machines currently active on Coston2**:

| Platform | Active machines | What it is |
|---|---|---|
| `TEST_PLATFORM` | **254** (94.8%) | **Simulated TEE.** `SIMULATED_TEE=true` / `MODE=1`. No enclave hardware. |
| `GCP_AMD_SEV` | 7 | Real Confidential Space on AMD SEV (includes Flare's own `tee-proxy-coston2-1/2`) |
| `GCP_INTEL_TDX` | 7 | Real Confidential Space on Intel TDX |

`[Measured — enumerated every address returned by `getAllActiveTeeMachines(0,300)` on
`FlareTeeManager` `0x1a9C4A0f9D76c0b1D91d22E24E573a9b377618aE` (Coston2) and called
`getTeeMachineWithAttestationData(address)` on each; script and raw output in §2.1. Read 2026-08-06.]`

And the simulated machines are not inert registry rows — they are **routable**:

```
$ cast call 0x1a9C4A0f9D76c0b1D91d22E24E573a9b377618aE \
    "getRandomTeeIds(uint256,uint256)(address[])" 65553 1 \
    --rpc-url https://coston2-api.flare.network/ext/C/rpc
[0x0fcAB6A37ce455113824aE1655143DD30946085a]
```

That address is a `TEST_PLATFORM` machine with the hardcoded simulated codeHash `0x194844cf…`, whose proxy URL
is `https://mixing-websites-scored-aqua.trycloudflare.com` — someone's laptop behind a Cloudflare tunnel.
`getRandomTeeIds` is the selection function `sendInstructions` uses. `[Verified — live chain read, 2026-08-06]`

**This directly contradicts Flare's own documentation**, which states in two places that FTDC rejects
simulated TEEs (§7.2). The chain is the authority; the docs are stale.

If you *do* self-provision GCP anyway, cost is not the blocker:

| Scenario (`n2d-standard-2`, Confidential Space SEV, us-central1) | Cost |
|---|---|
| (a) 8 days continuous | **$20.94** |
| (b) 30 days continuous | **$78.53** |
| (c) 30 days, 10 h × 22 weekdays only | **$25.36** |
| (b) on Spot | $25.98 (**do not** — §4.4) |

`[Measured — arithmetic in §4 from cloud.google.com price tables fetched 2026-08-06]`

The real blockers, if you go the GCP route, are in this order: **(1)** Confidential Space runs exactly one
container per VM, so you need a *second* non-confidential host for `ext-proxy` + `redis`; **(2)** a brand-new
Google Cloud Free Trial account is **forbidden from requesting a quota increase**, so a zero N2D quota is a
hard stop; **(3)** production Confidential Space images have SSH permanently disabled, which changes what
"give my engineer access" can even mean.

---

## 2. The correction: simulated TEEs work on Coston2 (the load-bearing finding)

### 2.1 How I established it

The `FlareTeeManager` diamond on Coston2 is `0x1a9C4A0f9D76c0b1D91d22E24E573a9b377618aE`
`[Verified — fce-sign/config/coston2/deployed-addresses.json, entry `FlareTeeManager`]`. Its
`MachineManagerFacet` is verified on the Coston2 explorer, so the ABI is retrievable:

```bash
curl -s "https://coston2-explorer.flare.network/api?module=contract&action=getabi\
&address=0xF40B9a2e70EE96042217F10D94A4B1eDf13096a8" | jq -r .result
```

Relevant view functions `[Verified — that ABI]`:

```
getAllActiveTeeMachines(uint256,uint256) -> (address[], string[], uint256)
getActiveTeeMachines(uint256)            -> (address[], string[])
getTeeMachineWithAttestationData(address)-> (address teeId, address initialTeeId,
                                             string url, bytes32 codeHash, bytes32 platform)
getTeeMachineStatus(address)             -> uint8
getRandomTeeIds(uint256 extensionId, uint256 count) -> address[]
getExtensionId(address)                  -> uint256
getLastStatusChangeTs(address)           -> uint256
```

The census:

```bash
export PATH="$PATH:$HOME/.foundry/bin"
R=https://coston2-api.flare.network/ext/C/rpc
D=0x1a9C4A0f9D76c0b1D91d22E24E573a9b377618aE

cast call $D "getAllActiveTeeMachines(uint256,uint256)(address[],string[],uint256)" 0 300 \
  --rpc-url $R | head -1 | tr -d '[]' | tr ',' '\n' | tr -d ' ' > machines.txt

while read m; do
  out=$(cast call $D \
    "getTeeMachineWithAttestationData(address)((address,address,string,bytes32,bytes32))" \
    $m --rpc-url $R)
  echo "$m $(echo "$out" | grep -oE '0x[0-9a-f]{64}' | tail -1)"
done < machines.txt
```

Result: **268 total, 254 `TEST_PLATFORM`, 7 `GCP_AMD_SEV`, 7 `GCP_INTEL_TDX`, 0 anything else.**
`[Measured — 2026-08-06]`

Every one of the sampled simulated machines carries codeHash
`0x194844cf417dde867073e5ab7199fa4d21fd82b5dbe2bdea8b3d7fc18d10fdc2` — byte-for-byte the `TeeCodeHash`
sentinel constant in Flare's own tooling `[Verified — fce-extension-scaffold/tools/pkg/fccutils/encoding.go:16]`
— and platform `0x544553545f504c4154464f524d…` = ASCII `TEST_PLATFORM`
`[Verified — same file, line 15; and `cast to-ascii` on the live value]`.

Sample rows, verbatim:

| teeId | status | codeHash | platform | proxy URL |
|---|---|---|---|---|
| `0x9fa3673E…35Cb6` | 2 | `0x194844cf…` | `TEST_PLATFORM` | `https://geographical-tristian-unexuberant.ngrok-free.dev` |
| `0xEb7Ef279…f9084` | 2 | `0x194844cf…` | `TEST_PLATFORM` | `https://redesigned-memory-…-6674.app.github.dev` |
| `0x0fcAB6A3…6085a` | 2 | `0x194844cf…` | `TEST_PLATFORM` | `https://mixing-websites-scored-aqua.trycloudflare.com` |
| `0x842df97e…e356B` | 2 | `0x194844cf…` | `TEST_PLATFORM` | `http://34.171.57.122:6664` |
| `0xC869a5db…e57C5` | 2 | `0x07e39451…` | `GCP_AMD_SEV` | `https://tee-proxy-coston2-1.flare.rocks` (Flare's own) |
| `0x5e4884b7…E0a01` | 2 | `0x5b75411c…` | `GCP_AMD_SEV` | `https://tee-proxy-coston2-transfers.flare.rocks` |
| `0xB7e6dC44…8F05B` | 2 | — | `GCP_INTEL_TDX` | — |

`[Verified — live reads, 2026-08-06]`

**Flare's own production machine and a laptop behind an ngrok tunnel have the identical on-chain status: `2`.**
Whatever the enum names that value, it is the state that `getAllActiveTeeMachines` and `getRandomTeeIds` treat
as live. `[Verified]`

`getLastStatusChangeTs` shows these are current, not fossils:

| Machine | Platform | Last status change |
|---|---|---|
| `0x0fcAB6A3…` | TEST_PLATFORM | 2026-07-20 09:44:56 UTC |
| `0x842df97e…` | TEST_PLATFORM | 2026-07-21 14:07:05 UTC |
| `0xC869a5db…` | GCP_AMD_SEV (Flare) | 2026-07-22 10:11:12 UTC |
| `0xB7e6dC44…` | GCP_INTEL_TDX | **2026-08-04 13:08:09 UTC** |

`[Verified — live reads]` The TDX machine transitioned two days ago, i.e. *during* this hackathon.

### 2.2 What this means, stated carefully

- **`SIMULATED_TEE=true` + `LOCAL_MODE=false` against real Coston2 reaches active, routable state.**
  `[Verified]` The `p` (to-production) step of `register-tee -command rRap`, which is gated on an FTDC
  availability-check proof, evidently succeeds for `TEST_PLATFORM` machines. 254 live examples.
- **`GCP_INTEL_TDX` is also accepted**, not just AMD SEV. `[Verified]` This resolves what the earlier pass
  listed as an open research question.
- **The tunnel URLs are the tell.** `ngrok-free.dev`, `trycloudflare.com`, `app.github.dev` (GitHub
  Codespaces), and bare `http://34.x.x.x:6664` GCE IPs. These are developers running `docker compose up` and
  `ngrok http 6674`, exactly as `fce-sign/.env.local.coston2` instructs. Several share a proxy URL, meaning one
  person registered many machines. `[Inference — from the URL shapes and the repeat hostnames; I cannot
  identify the operators.]`
- **What is still true:** a simulated TEE provides **no confidentiality guarantee**. The "enclave" is a Docker
  container on somebody's laptop with a hardcoded attestation. Anyone can read its memory. For Bounty 2
  ("Confidential Compute Apps") this is a real limitation you must be honest about — see §8.3.

### 2.3 Why Flare's docs say otherwise

Two primary-source statements say the opposite of what the chain shows:

> `SIMULATED_TEE` | `false` | Must be `false` on testnets. Tells `register-tee` to read the real codeHash from
> the proxy's `/info`. **FTDC rejects simulated TEEs.**

`[Verified — fce-sign/TESTNET_DEPLOYMENT.md, configuration table, line 201]`

> **`404` / `'not found': response not in storage` from FTDC normal proxy** … 1. **Simulated TEE** — Flare's
> Coston/Coston2 FTDC rejects `TEST_PLATFORM` / hardcoded simulated codeHash. Deploy on a real Confidential
> Space VM.

`[Verified — fce-sign/TESTNET_DEPLOYMENT.md, troubleshooting, line 691]`

> `MODE` and `SIMULATED_TEE` must agree or you'll see `code hashes do not match`. For testnet, both must point
> at "real": **`MODE=0` + `SIMULATED_TEE=false`**.

`[Verified — fce-sign/TESTNET_DEPLOYMENT.md, line 338]`

Yet the same repo ships `.env.local.coston2`, a first-class template whose header reads:

> Same as `.env.coston2` but runs a **SIMULATED TEE** behind a locally-run `ext-proxy` exposed via ngrok. The
> TEE container runs with `MODE=1`… `LOCAL_MODE=false` · `SIMULATED_TEE=true` ·
> `CHAIN_URL=https://coston2-api.flare.network/ext/C/rpc`

`[Verified — read the file]` — and `use-chain.sh --help` advertises `./use-chain.sh local coston2 go` as a
supported mode `[Verified — fce-sign/scripts/use-chain.sh, help text]`.

**Reconciliation `[Inference]`:** the prose was almost certainly accurate when written and the Coston2 FTDC
policy was subsequently relaxed — plausibly *for* this hackathon, given 254 tunnel-hosted registrations and a
TDX machine promoted on 2026-08-04. I cannot verify the intent, only the current state. **Treat this as a
policy that could change back.** The mitigation is in §8.1: verify on the day, and keep the GCP path costed
and ready.

`[Unverified]` — whether the Coston2 FTDC availability check will *still* accept `TEST_PLATFORM` on
2026-08-14. **Experiment:** re-run the §2.1 census immediately before the demo; if the `TEST_PLATFORM` count
has collapsed or your own machine's status leaves `2`, fall back to §5.

---

## 3. What is actually being deployed

If you do go to GCP, this is the shape of it. The Flare FCC stack is **three** containers and only **one**
goes inside the TEE.

| Container | Runs where | Why |
|---|---|---|
| `extension-tee` (your code + `tee-node`) | **Inside** the Confidential Space VM | It is the thing being attested |
| `ext-proxy` (`flare-foundation/tee-proxy`) | **Outside**, ordinary host | Needs a public HTTPS endpoint, a Redis, and a MySQL connection to Flare's indexer |
| `redis` | **Outside**, alongside `ext-proxy` | Proxy's queue store |

`[Verified — fce-sign/docker-compose.yaml defines exactly these three services; `ext-proxy` publishes
`6673→6663` (internal) and `6674→6664` (external); the extension image `EXPOSE`s 5501/7701/7702 only]`

**Confidential Space cannot host the other two.** "Confidential Space runs the container launcher, which in
turn launches a single container."
`[Verified — docs.cloud.google.com/confidential-computing/confidential-space/docs/create-customize-workloads]`
There is no docker-compose, no sidecar, no pod.

Confirmed empirically against Flare's own live deployment — I fetched and decoded their production Coston2
attestation JWT:

```bash
curl -s https://tee-proxy-coston2-1.flare.rocks/info \
  | jq -r .attestation | cut -d. -f2 \
  | python3 -c "import sys,base64,json;p=sys.stdin.read().strip();p+='='*(-len(p)%4);print(json.dumps(json.loads(base64.urlsafe_b64decode(p)),indent=2))"
```

```json
{
  "iss": "https://confidentialcomputing.googleapis.com",
  "sub": ".../projects/flare-network-staging/zones/europe-west1-b/instances/tee-machine-coston2-1",
  "hwmodel": "GCP_AMD_SEV",
  "swname": "CONFIDENTIAL_SPACE",
  "swversion": ["260600"],
  "secboot": true,
  "dbgstat": "enabled",
  "oemid": 11129,
  "submods": {
    "confidential_space": { "monitoring_enabled": { "memory": true } },
    "gce": { "zone": "europe-west1-b", "project_id": "flare-network-staging",
             "instance_name": "tee-machine-coston2-1", "instance_id": "3106492918438636414" },
    "container": {
      "image_reference": "europe-west1-docker.pkg.dev/flare-network-staging/containers/tee-node:v0.0.24-dev",
      "image_digest": "sha256:5093a9c46c573e6e87ef9caa55044010c9350ffd9c01853c2e58e45d73c57087",
      "image_id":     "sha256:07e394513282daf3e35daefaec9c9e3e1ba2b827ac84c51529566bfb78ae34cf",
      "restart_policy": "Never",
      "args": ["./server"],
      "env_override": {
        "CHAIN_ID": "114", "EXTENSION_ID": "0x00…00",
        "GOVERNANCE_SIGNERS": "0xfD5e6AbE2829966e86FE4ACC9c44784d251AE512",
        "GOVERNANCE_THRESHOLD": "1",
        "INITIAL_OWNER": "0xEfFDC9d60eaa243b2fCC5c2A21FA938B3A872d07",
        "LOG_LEVEL": "INFO",
        "PROXY_URL": "http://tee-proxy-coston2-1.flare-network-staging.internal"
      },
      "env": { "…": "…", "MODE": "0", "HOSTNAME": "tee-machine-coston2-1" }
    }
  },
  "google_service_accounts": ["confidential-sa@flare-network-staging.iam.gserviceaccount.com"]
}
```

`[Verified — live fetch, HTTP 200, 2026-08-06]`

Six facts fall out, each worth more than a page of docs:

1. **`PROXY_URL` is `…flare-network-staging.internal`** — the internal-DNS name of a *different* VM. The proxy
   is not in the enclave. `[Verified]`
2. **`hwmodel: GCP_AMD_SEV`** — Flare's own production Coston2 TEE is AMD SEV. Not SEV-SNP, not TDX. `[Verified]`
3. **`dbgstat: "enabled"`** ⇒ Flare runs the **`confidential-space-debug`** image family, not production.
   `[Verified — "In production images, the value is `disabled-since-boot`… In debug images, the value is
   `enabled`", docs.cloud.google.com/confidential-computing/confidential-space/docs/reference/token-claims]`
   A debug-image TEE is therefore an accepted Coston2 configuration, and it is SSH-able.
4. **`MODE: "0"`** is in the container `env` but *not* in `env_override` — it is baked into the image, exactly
   as `build-image.sh` enforces. `[Verified]`
5. **`restart_policy: "Never"`**, `monitoring_enabled.memory: true` ⇒ they set
   `tee-monitoring-memory-enable=true` and left `tee-restart-policy` at its default. `[Verified]`
6. **Zone `europe-west1-b`**, image pulled from `europe-west1-docker.pkg.dev` — Artifact Registry in the same
   region as the VM. `[Verified]`

### 3.1 How `codeHash` and `platform` are derived — verified against live data

The on-chain `machineData` for Flare's machine reads:

```json
{ "codeHash": "0x07e394513282daf3e35daefaec9c9e3e1ba2b827ac84c51529566bfb78ae34cf",
  "platform": "0x4743505f414d445f534556000000000000000000000000000000000000000000" }
```

`[Verified — https://tee-proxy-coston2-1.flare.rocks/info, live 2026-08-06; identical value returned by
`getTeeMachineWithAttestationData` on-chain]`

Compare to the JWT above:

- `platform` `0x4743505f414d445f534556…` is exactly ASCII `GCP_AMD_SEV` right-padded to 32 bytes — the
  `hwmodel` claim, verbatim. **`platform` is the ASCII of `hwmodel`.** `[Verified — value-level match]`
- `codeHash` `0x07e39451…` equals `submods.container.**image_id**`, **not** `image_digest` (`0x5093a9c4…`).
  **`codeHash` is the container image ID, not the registry digest and not a VM measurement.** `[Verified —
  value-level match; this distinction matters and is easy to get wrong]`

This is why reproducible builds dominate everything: the entire on-chain whitelist is keyed on a Docker image
ID. `SOURCE_DATE_EPOCH` drift ⇒ different `codeHash` ⇒ re-run `allow-tee-version` ⇒ re-register.

Flare's tooling is deliberately platform-agnostic — `allow-tee-version` whitelists whatever
`(codeHash, platform)` pair the proxy `/info` reports:

```go
var (
  PlatformIntel   = common.HexToHash("4743505f494e54454c5f544458…") // GCP_INTEL_TDX
  PlatformAMD     = common.HexToHash("4743505f414d445f534556…")     // GCP_AMD_SEV
  PlatformAMDESEV = common.HexToHash("4743505f414d445f5345565f4553…")// GCP_AMD_SEV_ES
  TestPlatform    = common.HexToHash("544553545f504c4154464f524d…") // TEST_PLATFORM
  TeeCodeHash     = common.HexToHash("194844cf417dde867073e5ab7199fa4d21fd82b5dbe2bdea8b3d7fc18d10fdc2")
)
```

`[Verified — fce-extension-scaffold/tools/pkg/fccutils/encoding.go:11-16, read at HEAD 2026-08-06]`

Those are the four legal GCP `hwmodel` values minus `GCP_SHIELDED_VM` (`GCP_AMD_SEV`, `GCP_AMD_SEV_ES`,
`GCP_SHIELDED_VM`, `GCP_INTEL_TDX`) `[Verified — token-claims reference]`, plus Flare's simulated sentinel.
The §2.1 census shows three of the four in live use.

---

## 4. Machine requirements

### 4.1 What Flare specifies

**Nothing.** No machine type, vCPU count, memory figure, boot disk size or image family appears anywhere in
`fce-extension-scaffold` or `fce-sign`, and neither repo contains a single `gcloud` command.

`[Verified — exhaustive grep of both repos at HEAD 2026-08-06 for
`n2d-|c2d-|c3d-|c4d-|machine-type|machine_type|boot-disk|vcpu|gcloud compute` across `*.md *.sh *.yaml *.go
Dockerfile* *.env*`. Exactly one hit: `fce-extension-scaffold/testing/README.md:52` — "Create a GCP
e2-standard-4 (4 vCPU, 16GB RAM) with Ubuntu 22.04 and 50GB disk", which is a **test-agent host**, not the
TEE. A separate `grep -rn gcloud` over both repos returns zero lines.]`

The reason is that the documented happy path is *Flare's devops runs the VM for you*:

> Devops deploys the image on a **GCP Confidential Space VM** with: `MODE` = `0` (already baked in) ·
> `EXTENSION_ID` (passed as a container env var) · `INITIAL_OWNER` · `CHAIN_URL` · `PROXY_URL` ·
> `ext-proxy` container with the right chain TOML · Public HTTPS URL routed to port `6664` of the proxy.
>
> Devops contact for deploying this extension: **Aljaž Konečnik**.

`[Verified — fce-sign/TESTNET_DEPLOYMENT.md, "Devops responsibilities", lines 394-409]`

And `tee-node`'s own deployment doc reduces GCP to four lines: build a reproducible image → push to Artifact
Registry → create a Confidential VM with it → the node reaches the attestation service over a Unix socket.
`[Verified — flare-foundation/tee-node, docs/deployment.md]`

### 4.2 What GCP requires

Confidential Space is a layer on Confidential VM: *"Confidential Space requires Confidential VM to work.
Confidential VM instances must use AMD SEV, Intel TDX, or Intel TDX with NVIDIA Confidential Computing."*
`[Verified — confidential-space-overview]`

| Technology | Machine series | CPU platform | Live migration |
|---|---|---|---|
| **AMD SEV** | **N2D, C2D, C3D, C4D** | EPYC Milan (N2D, C2D), Genoa (C3D), Turin (C4D) | Only AMD SEV on **Milan** (N2D/C2D) |
| AMD SEV-SNP | **N2D only** | EPYC Milan | Not supported |
| Intel TDX | `c3-standard-*`, `c4-standard-*` (Preview), `a3-highgpu-1g` | Sapphire Rapids / Granite Rapids | Not supported |

`[Verified — docs.cloud.google.com/confidential-computing/confidential-vm/docs/supported-configurations]`

SEV-SNP is additionally restricted to `asia-southeast1-a/b/c`, `europe-west3-a/b/c`, `europe-west4-a/b/c`,
`us-central1-a/b/c`. `[Verified — same page]`

### 4.3 Recommended spec

| Setting | Value | Basis |
|---|---|---|
| Machine type | **`n2d-standard-2`** (2 vCPU, 8 GiB) | Google's own Confidential Space examples use `n2d-standard-2` `[Verified — deploy-workloads doc]`; N2D+SEV is the only combination supporting live migration, avoiding a terminate-on-host-maintenance event that would destroy the TEE identity (§4.4) `[Inference from supported-configurations]` |
| Confidential type | **`SEV`** | Matches Flare's live production TEE `hwmodel=GCP_AMD_SEV` `[Verified — live JWT]`. TDX also demonstrably works on Coston2 (§2.1) but SEV is the known-good path. |
| Image project | `confidential-space-images` | `[Verified — deploy-workloads]` |
| Image family | **`confidential-space-debug`** | Flare's own Coston2 machine runs debug (`dbgstat: enabled`) `[Verified — live JWT]`, it is accepted, and it gives you SSH |
| Maintenance policy | `MIGRATE` (valid only for N2D+SEV) | `[Verified — create-a-confidential-vm-instance]` |
| Boot disk | 20 GiB `pd-balanced` (**modelled, not required**) | Google states no minimum for CPU workloads; "GPU workloads require 30 GB minimum" `[Verified — deploy-workloads]` |
| Shielded | `--shielded-secure-boot` (required) | `[Verified — deploy-workloads]` |

**Is 2 vCPU / 8 GiB enough?** Yes, with enormous margin. The workload is a `gcr.io/distroless/static` image
containing one statically-linked `CGO_ENABLED=0` Go binary plus the CA bundle — nothing else.
`[Verified — fce-sign/Dockerfile: `FROM gcr.io/distroless/static`, `EXPOSE 5501 7701 7702`]` It serves three
HTTP ports and polls a proxy. `n2d-standard-2` is the smallest N2D standard type, so this is the floor rather
than a sizing decision. `[Inference]`

---

## 5. Exact cost

### 5.1 Verified unit prices

All fetched 2026-08-06, Iowa (us-central1) unless noted.

**Confidential Computing premium** — a *flat* per-vCPU and per-GiB surcharge. The AMD SEV table carries **no
region selector**, i.e. it is region-independent:

| Technology | vCPU on-demand | vCPU Spot | Memory on-demand | Memory Spot |
|---|---|---|---|---|
| **AMD SEV** (N2D, C2D, C3D, C4D) | **$0.005479 /vCPU-hr** | $0.0012822 | **$0.0007342 /GiB-hr** | $0.0001712 |
| AMD SEV-SNP (N2D) | $0.0027502 | $0.000436 | $0.0003686 | $0.0000584 |
| Intel TDX (C3) | $0.0033982 | $0.001155 | $0.0004555 | $0.0001549 |

`[Verified — https://cloud.google.com/confidential-computing/confidential-vm/pricing, extracted from the
static HTML; the AMD SEV rows read verbatim "vCPUs $0.005479 / 1 hour … Memory $0.0007342 / 1 gibibyte hour"]`

Counter-intuitive but true: **SEV is the most expensive premium of the three** — SEV-SNP is roughly half the
per-vCPU price. SEV remains correct here because it is what Flare runs and SEV-SNP is zone-restricted.

**Base machine (us-central1):**

| Item | vCPU | Mem | On-demand | Spot |
|---|---|---|---|---|
| `n2d-standard-2` | 2 | 8 GiB | **$0.084492 /hr** | **$0.026912 /hr** |
| `n2d-standard-4` | 4 | 16 GiB | $0.168984 /hr | $0.053824 /hr |
| `e2-small` (proxy host) | 2 | 2 GiB | **$0.016752855 /hr** | — |

`[Verified — https://cloud.google.com/products/compute/pricing/general-purpose (row reads literally
"n2d-standard-2 / 2 / 8 GiB / $0.084492 / 1 hour") and https://cloud.google.com/spot-vms/pricing]`

**Storage, IP, egress:**

| Item | Price |
|---|---|
| Balanced PD provisioned space | **$0.000136986 /GiB-hr** (= $0.10 /GiB-month) |
| Standard PD provisioned space | $0.000054795 /GiB-hr (first 30 GiB-month free) |
| Ephemeral/static external IPv4, in use on a **standard** VM | **$0.005 /hr** |
| Ephemeral/static external IPv4, in use on a **Spot** VM | $0.0025 /hr |
| Static IPv4 reserved but **unused** | $0.01 /hr |
| Internet egress → North America, Premium Tier | **$0.12 /GiB** (first 1 GiB/month free) |
| VM↔VM, **same zone**, internal IP | **$0.00** |
| VM↔VM, different zone, same region | $0.01 /GiB |

`[Verified — https://cloud.google.com/compute/disks-image-pricing and
https://cloud.google.com/vpc/network-pricing]`

**Confidential Space itself has no separate SKU.** The Confidential VM pricing page states only that
Confidential VM incurs additional flat per-vCPU and per-GB costs; no Confidential Space line item and no
attestation-service price appear on it. `[Verified — absence on that page]`
`[Unverified]` that no attestation charge exists *anywhere*. **Experiment:** run a VM for 24 h and read the
billing export grouped by SKU, looking for `confidentialcomputing.googleapis.com`.

### 5.2 The arithmetic

Configuration: `n2d-standard-2`, `--confidential-compute-type=SEV`, 20 GiB pd-balanced boot disk, one
ephemeral external IPv4, us-central1.

```
Per-hour, on-demand
  base machine                                $0.0844920
  confidential premium, vCPU  2 × 0.005479    $0.0109580
  confidential premium, mem   8 × 0.0007342   $0.0058736
  boot disk                  20 × 0.000136986 $0.0027397
  external IPv4 (standard VM)                 $0.0050000
                                              ──────────
                                      TOTAL   $0.1090633 / hour

Per-hour, Spot
  base machine (spot)                         $0.0269120
  confidential premium, vCPU  2 × 0.0012822   $0.0025644
  confidential premium, mem   8 × 0.0001712   $0.0013696
  boot disk                  20 × 0.000136986 $0.0027397
  external IPv4 (Spot VM)                     $0.0025000
                                              ──────────
                                      TOTAL   $0.0360857 / hour
```

| Scenario | Hours | On-demand | Spot |
|---|---|---|---|
| **(a) 8 days continuous** | 192 | **$20.94** | $6.93 |
| **(b) 30 days continuous** | 720 | **$78.53** | $25.98 |
| **(c) 30 days, stopped outside working hours** | 220 run / 720 disk | **$25.36** | $9.31 |

`[Measured — from the §5.1 tables]`

**(c) worked in full.** Assumption: 10 h/day × 22 weekdays = 220 running hours. A *stopped* VM is not charged
for vCPU, memory or the confidential premium, and an **ephemeral** external IP is released on stop and
therefore not billed — *"For an ephemeral IP address, Google Cloud considers the address as in use only when
the associated VM instance is running"* `[Verified — vpc/network-pricing]`. The disk bills for all 720 h.

```
running components = 0.084492 + 0.010958 + 0.0058736 + 0.005 = $0.1063236 /hr
  × 220 h                                                    = $23.39
disk 0.0027397 × 720 h                                       = $ 1.97
                                                               ───────
                                                       TOTAL   $25.36
```

Using a **static** reserved IP instead adds $0.01/hr × 500 stopped hours = **+$5.00**, making (c) $30.36.
**Use an ephemeral IP.**

**Egress is negligible.** Put the proxy VM in the *same zone* and the TEE↔proxy leg is $0.00.

| Internet egress / month | Charge |
|---|---|
| 1 GiB | $0.00 (free tier) |
| 5 GiB | $0.48 |
| 20 GiB | $2.28 |

`[Measured — $0.12/GiB above 1 GiB/month]`

### 5.3 The second machine, which is easy to forget

`ext-proxy` + `redis` need a normal VM (§3). Minimum sane box:

```
e2-small (2 vCPU, 2 GiB)                    $0.016752855 /hr
20 GiB pd-balanced                          $0.0027397   /hr
external IPv4                               $0.0050000   /hr
                                            ─────────────
                                    TOTAL   $0.0244926   /hr
     → 8 days $4.70 · 30 days $17.63
```

`[Measured]`

**True total, both machines, on-demand: 8 days $25.64 · 30 days $96.16.** `[Measured]`

You can skip the second VM by running `ext-proxy` + `redis` locally behind a tunnel — which is what
`.env.local.coston2` does (`ngrok http 6674`) `[Verified]` and what 254 live Coston2 machines actually do
(§2.1). Caveat: the TEE reaches the proxy on the *internal* port 6663 and external callers on 6664
`[Verified — fce-sign/docker-compose.yaml maps `6673→6663` and `6674→6664`]`, so a naive single tunnel covers
only one role. In the fully-local topology this is a non-issue because the TEE reaches the proxy over the
Docker network at `http://ext-proxy:6663` `[Verified — docker-compose.yaml sets exactly that]`; the tunnel is
needed only for the *external* 6664 that Flare's FTDC proxy calls.

### 5.4 Spot: usable, but it costs you a re-registration

Spot **is** supported for Confidential VMs (`--provisioning-model=SPOT` with `--maintenance-policy=TERMINATE`)
`[Verified — create-a-confidential-vm-instance]`, and saves ~67%.

**What breaks on preemption is the TEE's on-chain identity.**

> A server running inside a Trusted Execution Environment (GCP Confidential Space). **It generates a fresh
> ECDSA key pair on each boot, which serves as its identity (`teeID`).** The private key never leaves the TEE.

`[Verified — flare-foundation/tee-node, docs/concepts.md]`

A preemption → restart yields a **new `teeID`**, and the on-chain record no longer matches. You must re-run
the whole pipeline: pre-register → fresh attestation → FTDC availability check → promote. There is no
shortcut — promotion (`p`) is gated on a proof obtainable only after step `a`:

```go
if strings.Contains(command, "p") {
    toProductionProof, err := GetFTDCAvailabilityCheckResult(ftdcTeeURL, instructionID)
    if err != nil { return err }
    err = ToProduction(s, toProductionProof)
    ...
}
```

`[Verified — fce-extension-scaffold/tools/pkg/fccutils/registration.go, `RegisterNode`]`

`post-build.sh` runs `register-tee … -command rRap` — register, Register-on-chain, availability-check,
promote — in one shot. `[Verified — fce-sign/scripts/post-build.sh, step 3]`

The backup/restore machinery does **not** help: it moves *wallet* keys between TEEs, not the node's own
identity keypair, and requires a >50% data-provider voting-weight quorum.
`[Verified — tee-node/docs/backup-restore.md]`

Also, `tee-restart-policy` defaults to `Never` `[Verified — cs-options reference]`, and Flare's live VM leaves
it at `Never` `[Verified — live JWT]` — a crashed container does not self-restart by default.

**Verdict: do not use Spot for the demo window.** Saving $14 over 8 days is not worth a coin-flip on whether
your TEE is registered when judges look. `[Inference]`

---

## 6. Free tier, credits, and the quota trap

### 6.1 The $300 credit

> "$300 in Welcome credit to spend over 90 days"

`[Verified — docs.cloud.google.com/free/docs/free-cloud-features]`

The credit **does** cover Confidential VMs — they are not excluded. The exclusions, verbatim, are things you
cannot do while your billing account is a non-billable Free Trial account:

> - "Add GPUs to your VM instances"
> - "Use Google Cloud Marketplace"
> - **"Request a quota increase"**
> - "Create VM instances that are based on Windows Server images"
> - "Create Google Cloud VMware Engine resources"

`[Verified — same page]`

At $78.53/month for the TEE VM, **$300 covers ~3.8 machine-months** — far more than this hackathon needs.
`[Measured]`

The Always Free tier is irrelevant: `1 non-preemptible e2-micro` in us-west1/us-central1/us-east1, 30 GB-months
standard PD, 1 GB North America egress `[Verified — same page]`. `e2-micro` cannot run Confidential VM at all
(E2 is absent from the SEV support matrix, §4.2). It *could* host `ext-proxy`, though 2 GiB is tight for
proxy + redis. `[Inference]`

### 6.2 The quota trap

**"Request a quota increase" is explicitly forbidden on a Free Trial account.** `[Verified]` The failure mode:
sign up → get $300 → try to create `n2d-standard-2` → hit a 0 or too-low `N2D_CPUS` quota → discover you
cannot file the increase → must upgrade to a paid billing account first → *then* file → then wait.

Google's quota documentation is deliberately vague about defaults:

> "Not all projects have the same quotas" … "some new accounts and projects also have a global
> `CPUs (All Regions)` quota"

`[Verified — docs.cloud.google.com/compute/resource-usage]`

`[Unverified]` — the exact default `N2D_CPUS` for a brand-new project in a given region. Google does not
publish it and it varies by account age, payment history and region. **Experiment, 60 seconds, run this
first:**

```bash
gcloud services enable compute.googleapis.com --project=PROJECT_ID

gcloud compute regions describe us-central1 --project=PROJECT_ID \
  --format="table(quotas.metric,quotas.limit,quotas.usage)" \
  | grep -Ei 'N2D_CPUS|^CPUS|IN_USE_ADDRESSES|DISKS_TOTAL_GB'
```

You need `N2D_CPUS >= 2` and `CPUS >= 2` in the target region, plus headroom for the proxy VM. If either is 0,
that is your blocker, not money.

Reported turnaround when you *are* allowed to ask: modest increases are often auto-approved within minutes;
new projects may be told *"If this is a new project please wait 48h until you resubmit the request or until
your Billing account has additional history."*
`[Unverified — this is a widely-reported Google response quoted in third-party sources, not an official SLA.
Experiment: file one and time it.]`

**Recommendation:** upgrade the billing account to paid *immediately* after claiming the $300. The credit is
still consumed first, and you regain the ability to request quota. `[Inference — the restriction attaches to
the "non-billable Free trial account" state, not to the credit itself, per the exclusion list wording.]`

---

## 7. Provisioning — the literal commands

Google's canonical template:

```
gcloud compute instances create INSTANCE_NAME \
        --confidential-compute-type=CONFIDENTIAL_COMPUTING_TECHNOLOGY \
        --machine-type=MACHINE_TYPE_NAME \
        --maintenance-policy=MAINTENANCE_POLICY \
        --shielded-secure-boot \
        --image-project=confidential-space-images \
        --image-family=IMAGE_FAMILY \
        --metadata="^~^tee-image-reference=us-docker.pkg.dev/WORKLOAD_AUTHOR_PROJECT_ID/REPOSITORY_NAME/WORKLOAD_CONTAINER_NAME:latest" \
        --service-account=WORKLOAD_SERVICE_ACCOUNT_NAME@WORKLOAD_OPERATOR_PROJECT_ID.iam.gserviceaccount.com \
        --scopes=cloud-platform \
        --zone=ZONE_NAME \
        --project=PROJECT_ID
```

`[Verified — verbatim from
docs.cloud.google.com/confidential-computing/confidential-space/docs/deploy-workloads]`

### 7.1 Full recipe for the Flare TEE node

```bash
export PROJECT_ID=trimmy-tee
export REGION=us-central1
export ZONE=us-central1-a
export REPO=trimmy
export SA=trimmy-tee-workload

# 0. APIs
gcloud services enable \
    compute.googleapis.com \
    artifactregistry.googleapis.com \
    confidentialcomputing.googleapis.com \
    logging.googleapis.com \
    --project="$PROJECT_ID"

# 1. Artifact Registry, in the SAME region as the VM
#    (Flare does this: europe-west1 VM, europe-west1-docker.pkg.dev image)
gcloud artifacts repositories create "$REPO" \
    --repository-format=docker --location="$REGION" --project="$PROJECT_ID"

gcloud auth configure-docker "${REGION}-docker.pkg.dev"

# 2. Push the reproducible extension image (built per fce-sign/scripts/build-image.sh)
export SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)
docker build -f go/Dockerfile \
    --build-arg SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
    -t trimmy-extension:v0.1.0 .
docker tag trimmy-extension:v0.1.0 \
    "${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/trimmy-extension:v0.1.0"
docker push "${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/trimmy-extension:v0.1.0"

# 3. Workload service account + minimum roles
gcloud iam service-accounts create "$SA" --project="$PROJECT_ID"
SA_EMAIL="${SA}@${PROJECT_ID}.iam.gserviceaccount.com"

for R in roles/confidentialcomputing.workloadUser \
         roles/logging.logWriter \
         roles/artifactregistry.reader; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member="serviceAccount:${SA_EMAIL}" --role="$R"
done

# 4. Create the Confidential Space VM
gcloud compute instances create trimmy-tee-1 \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --machine-type=n2d-standard-2 \
    --confidential-compute-type=SEV \
    --maintenance-policy=MIGRATE \
    --shielded-secure-boot \
    --image-project=confidential-space-images \
    --image-family=confidential-space-debug \
    --boot-disk-size=20GB \
    --boot-disk-type=pd-balanced \
    --service-account="$SA_EMAIL" \
    --scopes=cloud-platform \
    --metadata="^~^\
tee-image-reference=${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/trimmy-extension:v0.1.0~\
tee-container-log-redirect=cloud_logging~\
tee-restart-policy=Always~\
tee-monitoring-memory-enable=true~\
tee-env-MODE=0~\
tee-env-EXTENSION_ID=0x<from config/extension.env>~\
tee-env-INITIAL_OWNER=0x<your deployer address>~\
tee-env-CHAIN_URL=https://coston2-api.flare.network/ext/C/rpc~\
tee-env-PROXY_URL=http://<proxy-host>:6663~\
tee-env-LOG_LEVEL=INFO"
```

Notes, each load-bearing:

- **`^~^` is not decoration.** It sets `~` as the metadata delimiter so values containing commas and `://`
  survive. `[Verified — the `^~^` prefix appears in Google's own template]`
- **Every `tee-env-*` name must appear in the image's launch-policy label**, or the override is rejected at
  attestation time. The Flare extension images ship exactly:
  ```
  LABEL "tee.launch_policy.allow_env_override"="LOG_LEVEL,PROXY_URL,INITIAL_OWNER,EXTENSION_ID,CHAIN_URL,MODE,CONFIG_PORT,SIGN_PORT,EXTENSION_PORT"
  ```
  `[Verified — fce-sign/Dockerfile:66, read at HEAD; the same string is quoted in TESTNET_DEPLOYMENT.md:412]`
  **`CHAIN_ID` and `GOVERNANCE_*` are absent from this list.** They *are* present in `tee-node`'s own image
  label, which is why Flare's live JWT shows `CHAIN_ID` and `GOVERNANCE_SIGNERS` in `env_override`
  `[Verified — live JWT, §3]`. Note `docker-compose.yaml` *does* pass `CHAIN_ID` and `GOVERNANCE_*` to
  `extension-tee` `[Verified — read it]`, so this is a difference between the compose path and the
  Confidential Space path that will bite you. **If Trimmy needs `CHAIN_ID` or `GOVERNANCE_*` overridable at
  launch, add them to the `LABEL` and rebuild — which changes the `codeHash` and forces re-whitelisting.**
  `[Inference from the two labels + live JWT]`
- **`tee-env-MODE=0`.** Flare bakes `MODE=0` into the Dockerfile and `build-image.sh` verifies it
  `[Verified — TESTNET_DEPLOYMENT.md:345 "The Dockerfile bakes `MODE=0`; `docker-compose.yaml` overrides to
  `MODE=1` for local devnet only"]`. Passing it explicitly is belt-and-braces.
- **`tee-restart-policy=Always`** deviates from Flare's `Never`. Deliberate: a crash-restart yields a fresh
  `teeID` needing re-registration anyway, but at least the container comes back. `[Inference]`
- **Full metadata option set** `[Verified — cs-options reference]`: `tee-image-reference` (required),
  `tee-signed-image-repos`, `tee-restart-policy` (`Never`|`Always`|`OnFailure`, default `Never`), `tee-cmd`,
  `tee-env-NAME`, `tee-impersonate-service-accounts`, `tee-container-log-redirect`
  (`false`|`true`|`cloud_logging`|`serial`, default `false`), `tee-monitoring-memory-enable` (default
  `false`), `tee-mount`, `tee-added-capabilities`, `tee-cgroup-ns`, `tee-dev-shm-size-kb`,
  `tee-install-gpu-driver`, `ita-api-key`, `ita-region`.

### 7.2 Firewall

The TEE node makes **outbound** connections only — it polls the proxy and reaches the attestation service over
a Unix socket at `/run/container_launcher/teeserver.sock`, not the network.
`[Verified — tee-node/docs/attestation.md]` Default GCP egress is allowed, so **no ingress rule is needed for
the TEE VM, and none should be added.**

The **proxy** host needs ingress. Public HTTPS must reach port `6664`
`[Verified — fce-sign/TESTNET_DEPLOYMENT.md devops table]`, and the TEE must reach `6663`:

```bash
# proxy host only — never the TEE VM
gcloud compute firewall-rules create trimmy-proxy-external \
    --project="$PROJECT_ID" --network=default \
    --allow=tcp:6664 --target-tags=trimmy-proxy \
    --source-ranges=0.0.0.0/0

gcloud compute firewall-rules create trimmy-proxy-internal \
    --project="$PROJECT_ID" --network=default \
    --allow=tcp:6663 --target-tags=trimmy-proxy \
    --source-ranges=10.128.0.0/9
```

`[Inference — port numbers verified from fce-sign/docker-compose.yaml and TESTNET_DEPLOYMENT.md; the rules
themselves are constructed, not quoted]`

> **Security note.** Exposing 6664 to `0.0.0.0/0` means anyone with the URL can call the proxy HTTP API. The
> same warning applies to `ngrok http 6674`. Use it only for testnet, and shut it down afterwards.

### 7.3 Verifying the deploy

```bash
curl -s "$EXT_PROXY_URL/info" | jq '.machineData'
```

| Field | Must be |
|---|---|
| `platform` | starts `0x4743505f414d445f534556…` (GCP_AMD_SEV) |
| `codeHash` | a real measured hash — **not** `0x194844cf…` (the simulated sentinel) |
| `extensionId` | matches `config/extension.env` |
| `initialOwner` | matches your derived `INITIAL_OWNER` |
| `attestation` | a long base64 GCP JWT |

`[Verified — the exact `/info` shape, confirmed by live fetch: keys are
`attestation, dataSignature, machineData, proxySignature, teeInfo`]`

Decode what the VM actually saw at launch:

```bash
curl -s "$EXT_PROXY_URL/info" | jq -r .attestation | cut -d. -f2 \
  | python3 -c "import sys,base64,json;p=sys.stdin.read().strip();p+='='*(-len(p)%4);print(json.dumps(json.loads(base64.urlsafe_b64decode(p)).get('submods',{}).get('container',{}).get('env_override'),indent=2))"
```

(Use the Python form, not `base64 -d` — the JWT is base64url and unpadded, and `base64 -d` fails on it. I hit
this.) `[Verified — reproduced the failure and the fix, 2026-08-06]`

And confirm on-chain:

```bash
cast call 0x1a9C4A0f9D76c0b1D91d22E24E573a9b377618aE \
  "getTeeMachineStatus(address)(uint8)" $TEE_ID \
  --rpc-url https://coston2-api.flare.network/ext/C/rpc     # expect 2
cast call 0x1a9C4A0f9D76c0b1D91d22E24E573a9b377618aE \
  "getRandomTeeIds(uint256,uint256)(address[])" $EXTENSION_ID 1 \
  --rpc-url https://coston2-api.flare.network/ext/C/rpc     # expect your teeId
```

`[Verified — both commands run successfully against live Coston2, §2.1]`

Your `teeID` is derivable from the public key `/info` reports:

```bash
cast keccak 0x<pubkey.x><pubkey.y>   # take the last 20 bytes
```

`[Verified — I derived `0xC869a5db4A82055046209d12216624fD400e57C5` from Flare's reported public key this way
and it matched the address returned by `getActiveTeeMachines(0)`]`

---

## 8. Granting the engineer access

First, the fact that reframes the question:

**On the production `confidential-space` image, SSH is disabled and nobody — including the project owner — has
root on the VM.** *"the production image … is locked down to prevent the workload operator from accessing the
processed data"*; the debug image *"runs an SSH server to let you remotely log into the VM"* and *"the operator
has root access to the VM that runs the workload."*
`[Verified — docs.cloud.google.com/confidential-computing/confidential-space/docs/confidential-space-images
and .../monitor-debug]`

So "share SSH access" is only coherent on the **debug** image — which is what Flare themselves run on Coston2
(`dbgstat: "enabled"`, §3).

### 8.1 The four options

| # | Option | What the engineer can do | The risk | Verdict |
|---|---|---|---|---|
| **a** | Create the VM yourself, share SSH / IAP tunnel | Read container logs, poke the VM | Only works on the *debug* image, where they have **root** — the confidentiality guarantee is void. And they still can't redeploy a new image, so you become a bottleneck on every rebuild. | **No.** Maximum exposure, minimum usefulness. |
| **b** | Service-account JSON key handed over | Everything the SA can do, from anywhere | A downloadable long-lived credential: no expiry, no MFA, no per-person attribution, nothing stopping it landing in a repo. This project's own upstream demonstrates the failure — `fce-sign/.env.coston2` in the **public** Flare repo contains a literal `DEPLOYMENT_PRIVATE_KEY="1f467319d03602f91f54ace155a7a6f1f05537d81aea9abe83ae2030212b9524"` and the same value as `PROXY_PRIVATE_KEY`. `[Verified — read the file]` Key material leaks. | **No**, unless the engineer's machine has no Google identity at all. |
| **c** | Grant the engineer's own Google identity scoped IAM roles on the project | Create/manage the TEE VM, push images | Scoped, revocable in one command, attributable in audit logs, MFA-backed by their own account. | **Yes — the sane default.** |
| **d** | Share the whole project (Owner/Editor) | Everything, including billing and project deletion | Editor can grant *themselves* more; Owner can lock you out. | **No.** |

### 8.2 The minimum role set for option (c)

Two jobs, two grants.

**Job 1 — build and push the container image:**

```bash
gcloud artifacts repositories add-iam-policy-binding trimmy \
    --location=us-central1 --project=trimmy-tee \
    --member="user:engineer@example.com" \
    --role="roles/artifactregistry.writer"
```

This is a **repository-level** binding, not project-level — they can push to `trimmy` and nothing else.

**Job 2 — create, start, stop and delete the Confidential VM:**

```bash
gcloud projects add-iam-policy-binding trimmy-tee \
    --member="user:engineer@example.com" \
    --role="roles/compute.instanceAdmin.v1"

# Required because the VM runs AS a service account — without this,
# instance creation with --service-account is denied.
gcloud iam service-accounts add-iam-policy-binding \
    trimmy-tee-workload@trimmy-tee.iam.gserviceaccount.com \
    --project=trimmy-tee \
    --member="user:engineer@example.com" \
    --role="roles/iam.serviceAccountUser"
```

The `serviceAccountUser` requirement is explicit: *"If the instance runs as a service account, the
`roles/iam.serviceAccountUser` role must also be granted."*
`[Verified — docs.cloud.google.com/compute/docs/access]` Scoping it to the **one** service account rather than
project-wide is the important detail — project-wide `serviceAccountUser` lets them impersonate every SA you
ever create.

**Optional, for reading workload logs:**

```bash
gcloud projects add-iam-policy-binding trimmy-tee \
    --member="user:engineer@example.com" --role="roles/logging.viewer"
```

**Deliberately NOT granted:** `roles/owner`, `roles/editor`, `roles/iam.securityAdmin`, `roles/billing.admin`,
`roles/resourcemanager.projectIamAdmin`. The engineer can run the TEE; they cannot escalate, cannot spend
beyond compute, cannot delete the project.

**Revoke in one line:**

```bash
gcloud projects remove-iam-policy-binding trimmy-tee \
    --member="user:engineer@example.com" --role="roles/compute.instanceAdmin.v1"
```

**Set a budget alert** — the one guard IAM does not give you:

```bash
gcloud billing budgets create \
    --billing-account="$BILLING_ACCOUNT_ID" \
    --display-name="trimmy-tee cap" \
    --budget-amount=150USD \
    --threshold-rule=percent=0.5 --threshold-rule=percent=0.9 --threshold-rule=percent=1.0
```

`[Inference — standard `gcloud billing budgets` command shape; not quoted from a fetched page]`

### 8.3 The option that is probably right, given §2

**Grant nothing, because there is nothing to grant.** With simulated TEEs demonstrably active and routable on
Coston2 (§2), the engineer needs only:

- a funded Coston2 key (faucet: https://faucet.flare.network/coston2),
- Docker + Go,
- `ngrok`/`cloudflared` for the 6664 tunnel.

Zero GCP account, zero IAM, zero cost, zero quota risk. This is what 254 of 268 live machines do.

The fallback, in preference order: **(1)** ask Flare devops (**Aljaž Konečnik**, named in
`fce-sign/TESTNET_DEPLOYMENT.md`) to host it — the documented primary path, free, but with a lead time you do
not control eight days before a deadline `[Verified — the devops hand-off checklist exists and names him]`;
**(2)** self-provision per §7 and grant option (c).

---

## 9. Alternatives and what a simulated TEE actually costs you

### 9.1 Is any non-GCP provider viable?

**No, not for a real attestation, without changing `tee-node`.** The node's production attestation path is
hard-wired to Confidential Space: it POSTs to `/v1/token` on the Unix socket
`/run/container_launcher/teeserver.sock`, parses a Google JWT, derives `platform` from `hwmodel` and
`codeHash` from `submods.container.image_id`.
`[Verified — tee-node/docs/attestation.md; and confirmed by value-level match against the live JWT, §3.1]`
AWS Nitro Enclaves and Azure Confidential Containers produce entirely different attestation formats. There is
no abstraction layer to swap.

**Within GCP you have more room than the docs suggest, and this is now settled empirically:** 7 active
Coston2 machines run `GCP_INTEL_TDX` (§2.1), one promoted on 2026-08-04. So `c3-standard-*` with
`--confidential-compute-type=TDX` is accepted by Flare's Coston2 FTDC. `[Verified — live chain]` SEV remains
the recommendation because it is what Flare's own machines run and what their docs describe.

### 9.2 What `SIMULATED_TEE=true` / `MODE=1` actually does

Exactly one thing: it makes the *client-side tool* skip JWT parsing and substitute hardcoded values.

```go
func GetCodeHashAndPlatform(teeInfo *types.SignedTeeInfoResponse) (common.Hash, common.Hash, error) {
    simulatedTee := os.Getenv("SIMULATED_TEE") == "true"
    codeHash := TeeCodeHash      // 0x194844cf…
    platform := TestPlatform     // TEST_PLATFORM
    var err error
    if !simulatedTee {
        codeHash, platform, err = CodeHashAndPlatform(string(teeInfo.TeeInfoResponse.Attestation))
        if err != nil { return common.Hash{}, common.Hash{}, err }
    }
    if codeHash != teeInfo.MachineData.CodeHash {
        return ..., errors.Errorf("code hashes do not match: %s, %s", codeHash, teeInfo.MachineData.CodeHash)
    }
    if platform != teeInfo.MachineData.Platform {
        return ..., errors.Errorf("platforms do not matc: %s, %s", platform, teeInfo.MachineData.Platform)
    }
    return codeHash, platform, nil
}
```

`[Verified — fce-extension-scaffold/tools/pkg/fccutils/common.go, read verbatim at HEAD 2026-08-06 —
including the `do not matc` typo]`

It skips **no** on-chain step. `post-build.sh` still runs `allow-tee-version` (whitelisting `TEST_PLATFORM` +
`0x194844cf…`), still runs `set-governance`, still runs `register-tee -command rRap` whose `a` step calls
Flare's real FTDC proxy and whose `p` step needs a real FTDC proof. `[Verified — read post-build.sh]`

**And per §2, that pipeline completes.** 254 live machines are the proof.

`MODE` and `SIMULATED_TEE` must agree, or `GetCodeHashAndPlatform` fails with `code hashes do not match`:

| | `MODE` (TEE binary env) | `SIMULATED_TEE` (scripts) |
|---|---|---|
| Real | `0` — real GCP JWT | `false` — read real codeHash from `/info` |
| Simulated | `1` — hardcoded attestation | `true` — use hardcoded test codeHash |

`[Verified — fce-sign/TESTNET_DEPLOYMENT.md:336-345]`

### 9.3 What you genuinely lose

Be precise about this, especially for Bounty 2.

**You still get, and can demo, all of this:**

- A real `InstructionSender` contract deployed on real Coston2, with an explorer link. `[Verified — pre-build.sh
  deploys it; `.env.local.coston2` sets `CHAIN_URL=https://coston2-api.flare.network/ext/C/rpc` and
  `LOCAL_MODE=false`]`
- A real `EXTENSION_ID` minted on the real `TeeExtensionRegistry`.
- A real TEE machine row in the real on-chain `MachineManager`, in status `2`, returned by `getRandomTeeIds`.
  `[Verified — §2.1]`
- Real `sendInstructions` transactions, real `TeeInstructionsSent` events, real handler execution, real
  results signed by the node's real ECDSA identity key and verified on-chain.
- Real governance-hash binding (`set-governance` + `InvalidGovernanceHash` enforcement).

**You lose exactly one thing: the hardware root of trust.**

- `platform` is `TEST_PLATFORM`, not `GCP_AMD_SEV` — visibly, on-chain, to anyone who looks.
- `codeHash` is the constant `0x194844cf…`, identical across every simulated machine on the network. It
  therefore proves nothing about *which code* is running. The whole point of `codeHash` — that the on-chain
  whitelist pins a specific reproducible image — is inoperative.
- The "enclave" is a container on a laptop. Its memory is readable, its keys are extractable, its operator can
  lie about results. The confidentiality and integrity guarantees are simulated, not enforced.

**For a Bounty 2 submission this must be stated plainly.** The honest framing is strong: *"the FCC integration
is real and on-chain; the enclave is simulated, as are 254 of the 268 TEE machines currently active on
Coston2. Here is the exact `gcloud` command and the $21 that swaps in real AMD SEV hardware without a single
code change."* Claiming a real TEE while running `MODE=1` would be caught in ten seconds by anyone who curls
`/info` and sees `0x194844cf…`. `[Inference]`

### 9.4 Demonstration levels

- **`LOCAL_MODE=true` devnet** — attestation skipped, chain local. Proves handler logic, `OPType`/`OPCommand`
  routing, contract, encode/decode. Proves nothing about Flare integration.
- **`SIMULATED_TEE=true` + `LOCAL_MODE=false` on Coston2** — everything above, plus real on-chain identity,
  registration, routing and instruction execution. **This is the level to ship.**
- **`MODE=0` on real Confidential Space** — adds the hardware root of trust and nothing else functional.

`[Verified — the three configurations correspond exactly to `.env.example` / `.env.local.coston2` /
`.env.coston2` in fce-sign]`

---

## 10. Recommendations for Trimmy

1. **Build for `SIMULATED_TEE=true` + `LOCAL_MODE=false` on Coston2 as the primary path.** It is proven live
   (§2), it is what the overwhelming majority of active Coston2 TEE machines do, and it costs nothing. GCP is
   off the critical path.
2. **Re-run the §2.1 census on demo day**, and again the morning of 2026-08-14. It is a 3-minute script. The
   single risk to the plan is Coston2 FTDC policy tightening back to what the docs claim. Keep the output as
   evidence in the submission.
3. **Register early, not on the 13th.** Registration is `pre-build.sh` → hand `EXTENSION_ID` in → `post-build.sh`,
   and the FTDC availability check depends on Flare-side services (signing-policy sync, indexer liveness) that
   have documented failure modes you do not control. `[Verified — the `CheckFTDCProxyPolicyConsistency`
   preflight and the 404 troubleshooting entry both exist because this fails in practice]`
4. **Use a stable tunnel.** `.env.local.coston2` warns that ngrok's URL must be stable across restarts because
   it is written on-chain as the machine's `url` `[Verified]`. Use a reserved ngrok domain or a named
   Cloudflare tunnel. A rotating URL means a dead machine row.
5. **Be explicit about the simulation in the submission.** §9.3 gives the framing. Include the `gcloud`
   command from §7.1 and the $20.94/8-day figure — "one command and $21 from real hardware" is a much better
   story than a vague claim.
6. **If you do provision GCP:** check quota *first* (§6.2), upgrade billing to paid immediately so you can
   file increases, budget **$25.64 for 8 days across both machines**, use `confidential-space-debug`, use an
   ephemeral IP, and **do not use Spot** (§5.4).
7. **Grant the engineer option (c)** if GCP happens: repo-scoped `roles/artifactregistry.writer` + project
   `roles/compute.instanceAdmin.v1` + SA-scoped `roles/iam.serviceAccountUser`. **Never hand over a JSON key.**
   Set a $150 budget alert.
8. **Plan the proxy host from day one.** Confidential Space is one container per VM; `ext-proxy` + `redis`
   live elsewhere. Local + tunnel (free) or `e2-small` same-zone ($17.63/mo, egress free).
9. **Pin `SOURCE_DATE_EPOCH` and use the Go path.** `codeHash` *is* the container image ID (§3.1) — a
   non-reproducible build changes the hash and forces re-whitelisting plus re-registration. Go builds
   bit-for-bit reproducibly; Python/TypeScript images do not.
   `[Verified — fce-sign/REPRODUCIBILITY.md and the `SOURCE_DATE_EPOCH` build arg in docker-compose.yaml]`
10. **If Trimmy needs `CHAIN_ID` or `GOVERNANCE_*` overridable at launch, add them to
    `tee.launch_policy.allow_env_override` in the Dockerfile** — the shipped extension label omits both, even
    though `docker-compose.yaml` sets them (§7.1). Changing the label changes the `codeHash`.
11. **Never reuse `fce-sign/.env.coston2`'s committed private key**
    (`1f467319d03602f91f54ace155a7a6f1f05537d81aea9abe83ae2030212b9524`). It is public, it is in Flare's own
    repo, and anyone can spend from and impersonate it. Generate your own. `[Verified — read the file]`

---

## 11. Open questions

| # | Question | Experiment | Priority |
|---|---|---|---|
| 1 | Will Coston2 FTDC still accept `TEST_PLATFORM` on 2026-08-14? | Re-run the §2.1 census; check your own machine's `getTeeMachineStatus` is still `2`. | **High — this is the plan's only real risk** |
| 2 | What does `TeeStatus` enum value `2` literally mean? I established it functionally (returned by `getActiveTeeMachines` and `getRandomTeeIds`) but did not find the enum declaration — the explorer's verified `MachineManagerFacet` source is only the facet, and `IMachineManager.sol` was not in it. | Fetch `IMachineManager.sol` from `@flarenetwork/flare-periphery-contracts` and read `enum TeeStatus`. | Low — functional behaviour already verified |
| 3 | Default `N2D_CPUS` / `CPUS` quota in a brand-new project+region | `gcloud compute regions describe us-central1 --format="table(quotas.metric,quotas.limit,quotas.usage)"` | Medium (only if GCP path) |
| 4 | Actual quota-increase turnaround for a new paid account | File one for `N2D_CPUS=8` and time it. The 48 h figure is third-party, not an SLA. | Low |
| 5 | Default boot disk size of `confidential-space-debug` (I modelled 20 GiB by choice) | `gcloud compute images describe-from-family confidential-space-debug --project=confidential-space-images --format='value(diskSizeGb)'` | Low |
| 6 | Any billed SKU for Confidential Space / attestation beyond the CVM premium? | Run a VM 24 h; read billing export grouped by SKU. | Low |
| 7 | europe-west1 (Flare's region) exact `n2d-standard-2` price — I verified us-central1 only | Region selector on cloud.google.com/products/compute/pricing/general-purpose. The **confidential premium is region-independent** (verified: that table has no region selector); only the base machine price moves. | Low |
| 8 | Are the 254 `TEST_PLATFORM` machines hackathon participants? | Not directly answerable; inferred from tunnel-URL shapes and July/August timestamps. Would need the registering EOAs cross-referenced against hackathon signups. | Curiosity only |

---

## Appendix: sources

All fetched, read, or executed 2026-08-06.

**Live chain reads (Coston2, `https://coston2-api.flare.network/ext/C/rpc`, chainId 114):**
- `FlareTeeManager` `0x1a9C4A0f9D76c0b1D91d22E24E573a9b377618aE` —
  `getAllActiveTeeMachines`, `getActiveTeeMachines`, `getTeeMachineWithAttestationData`,
  `getTeeMachineStatus`, `getRandomTeeIds`, `getExtensionId`, `getLastStatusChangeTs`, `getTeeMachine`
- `MachineManagerFacet` ABI + source via
  `https://coston2-explorer.flare.network/api?module=contract&action=getabi&address=0xF40B9a2e70EE96042217F10D94A4B1eDf13096a8`
- `https://tee-proxy-coston2-1.flare.rocks/info` — HTTP 200, attestation JWT decoded (§3)

**Flare code (cloned at HEAD and read):**
- `github.com/flare-foundation/fce-extension-scaffold` — `docs/deployment-steps.md`, `docker-compose.yaml`,
  `go/Dockerfile`, `testing/README.md`, `tools/pkg/fccutils/{encoding,common,registration}.go`,
  `tools/cmd/{allow-tee-version,register-tee}/main.go`
- `github.com/flare-foundation/fce-sign` — `TESTNET_DEPLOYMENT.md`, `Dockerfile`, `proxy/Dockerfile`,
  `docker-compose.yaml`, `.env.coston2`, `.env.local.coston2`, `scripts/{use-chain,post-build,build-image}.sh`,
  `config/coston2/deployed-addresses.json`, `REPRODUCIBILITY.md`
- `github.com/flare-foundation/tee-node` — `docs/{deployment,attestation,concepts,backup-restore}.md`

**Google Cloud (primary):**
- `cloud.google.com/confidential-computing/confidential-vm/pricing`
- `cloud.google.com/products/compute/pricing/general-purpose`
- `cloud.google.com/spot-vms/pricing`
- `cloud.google.com/compute/disks-image-pricing`
- `cloud.google.com/vpc/network-pricing`
- `.../confidential-vm/docs/supported-configurations`, `.../create-a-confidential-vm-instance`,
  `.../reference/cs-options`
- `.../confidential-space/docs/{confidential-space-overview, deploy-workloads, confidential-space-images,
  monitor-debug, create-customize-workloads, reference/token-claims}`
- `docs.cloud.google.com/free/docs/free-cloud-features`, `.../compute/resource-usage`, `.../compute/docs/access`

**Security note on a source.** `fce-sign/.env.coston2` in the public Flare repo contains literal
`DEPLOYMENT_PRIVATE_KEY` and `PROXY_PRIVATE_KEY` values (`1f467319d0…`). Coston2 testnet keys, but publicly
readable and reusable by anyone — a live illustration of why option (b) in §8.1 is rejected.
