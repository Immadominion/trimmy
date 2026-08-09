# Flare Confidential Compute (FCC) — Trimmy Private-Trigger Extension

**Research doc for Bounty 2 ("Confidential Compute Apps"), Flare Summer Signal hackathon.**

Author: research agent `fcc-extension`
Date: 2026-08-06
Status: primary-source verified against repos pinned at current `main`, live Coston2 chain reads, and the Flare verifier config on GitHub.

**Re-verification pass (2026-08-06, second session).** Every load-bearing claim below was independently re-checked against freshly cloned repos rather than carried forward on trust. Results:

- All six defects (a)–(f) **re-confirmed** on fresh clones at the same `main` commits (upstream has not moved).
- `tee-node` **`v0.0.25` is still `@latest`** (2026-08-05); `tee-proxy` `@latest` is `v0.0.21`.
- The `POST /direct` credential channel — the crux of the whole design — **confirmed line by line**, including its config struct, API-key check, system-OPType rejection, and action construction.
- **Four new findings were added in this pass**, all design-critical:
  1. §2.6b — the handler's synchronous budget is a hard-coded **2 s** (`ProxyTimeout`, a Go `const`). This forces `EVAL` to be asynchronous and **resolves former open question #4**.
  2. §2.6 — an `ActionResponse` carries **two** signatures under **two** domains; a contract must verify `signature`, not `proxySignature`.
  3. §2.6 — the TEE signing payload is now verified from the **Go** side (`go-flare-common/pkg/signing`), not just inferred from Solidity.
  4. §5.3 — the `/direct` message-shape constraint is upgraded from `[Inference]` to `[Verified]` by reading `DirectInstructionToAction` directly.

Every claim below carries one of:

- `[Verified]` — read in source I actually opened, or a live chain/HTTP read I actually performed
- `[Measured]` — a number I computed from a cited experiment
- `[Inference]` — reasoned from `[Verified]` facts; the basis is stated
- `[Unverified]` — not established; the exact experiment that would settle it is stated

---

## 0. Repositories examined (exact commits)

All three repos were verified to be at current `origin/HEAD` via `git ls-remote` at time of writing. `[Verified]`

| Repo | Commit at `main` | Date |
|---|---|---|
| `flare-foundation/fce-extension-scaffold` | `f48cafb889441a62e47c083f4be8dd7d3f456f83` | 2026-07-28 |
| `flare-foundation/fce-sign` | `6df972c64d34efe1d4497f0eafe6792d1f0862dd` | 2026-07-28 |
| `flare-foundation/fce-weather-insurance` | `8d569a75756bb411bc2b7c6456f6b173b11d1333` | 2026-07-20 |

Supporting repos read (not part of the assignment but load-bearing for the findings):

| Repo | Ref | Why it mattered |
|---|---|---|
| `flare-foundation/tee-node` | tags `v0.0.21` … `v0.0.25` | The version-pin defect; the sign-port API; the attestation claim set |
| `flare-foundation/tee-proxy` | working tree | `POST /direct` — the off-chain ingress that solves credential delivery |
| `flare-foundation/go-flare-common` | working tree | `op.IsValidPair` — the OPType naming constraint |
| `flare-foundation/verifier-indexer-api` | `main` | The Web2Json source allow-list — this *changes our framing of the premise* |

Local working copies: `/private/tmp/claude-502/-Users-mac-Documents-codes-opensauce-flare/5b2318cb-1533-454e-a894-97fe6435f6fe/scratchpad/fcc/`

---

## 1. The premise, corrected and strengthened

The brief states: *"Web2Json's sourceId is literally `PublicWeb2` — the request and its headers go on-chain and ~100 providers fetch it, so any API key in a header is public."*

The conclusion (Web2Json cannot reach authenticated per-user data) is **correct**. The stated reason is **incomplete**, and the real reason is a much stronger argument. Use the corrected version in the submission.

### 1.1 What I actually verified

`[Verified]` The Web2Json request body has a `headers` field — a stringified JSON object of key/value pairs, one of seven required request fields (`url`, `httpMethod`, `headers`, `queryParams`, `body`, `postProcessJq`, `abiSignature`).
Source: <https://dev.flare.network/fdc/attestation-types/web2-json>

`[Verified]` The set of legal `sourceId` values is **not open**. It is a hardcoded allow-list compiled into the verifier service. I read both config files directly:

Testnet — `verifier-indexer-api/src/config/web2/web2-json-test-sources.ts`:

```ts
/**
 * Special source allowing access to any public Web2 JSON endpoint without restrictions.
 * Only available on testnets.
 */
export const PUBLIC_WEB2: Web2JsonSource = {
  sourceId: 'PublicWeb2',
  endpoints: [],
};

export const WEB2_JSON_TEST_SOURCES: Web2JsonSource[] = [
  PUBLIC_WEB2,
  {
    sourceId: 'testIgnite',
    endpoints: [
      {
        host: 'api-proxy-dev.ignitemarket.xyz',
        paths: '*',
        methods: [HTTP_METHOD.GET],
        auth: { type: AuthType.APIKEY, env: 'IGNITE_API_KEY', header: 'x-api-key' },
      },
    ],
  },
];
```

Mainnet — `verifier-indexer-api/src/config/web2/web2-json-sources.ts`:

```ts
export const WEB2_JSON_SOURCES: Web2JsonSource[] = [
  {
    sourceId: 'Ignite',
    endpoints: [
      {
        host: 'api-proxy.ignitemarket.xyz',
        paths: '*',
        methods: [HTTP_METHOD.GET],
        auth: { type: AuthType.APIKEY, env: 'IGNITE_API_KEY', header: 'x-api-key' },
      },
    ],
  },
];
```

Raw URLs (both fetched HTTP 200):
- <https://raw.githubusercontent.com/flare-foundation/verifier-indexer-api/main/src/config/web2/web2-json-test-sources.ts>
- <https://raw.githubusercontent.com/flare-foundation/verifier-indexer-api/main/src/config/web2/web2-json-sources.ts>

`[Verified]` The auth model is defined in `src/config/interfaces/web2-json.ts`:

```ts
export interface EndpointAuth {
  type: AuthType;
  /** Name of the header field to pass the secret, if applicable. */
  header?: string;
  /** Name of the query parameter to pass the secret, if applicable. */
  query?: string;
  /** Name of the environment variable that holds the secret at runtime. */
  env?: string;
}
export enum AuthType { BEARER = 'bearer', APIKEY = 'apikey' }
```

### 1.2 The corrected argument (use this one)

Web2Json **does** support authenticated endpoints — but the credential is `env`-injected **by the verifier operator, per allow-listed host, shared network-wide**. It is one key for the whole of Flare, negotiated with the Flare Foundation, bound to a specific DNS host.

This gives three independent, structural blockers for Trimmy: `[Inference]`, from the three `[Verified]` reads above.

1. **Per-user credentials are not expressible.** The `EndpointAuth` schema has exactly one `env` var name per endpoint. There is no field that could carry *a caller's own* API key. Ten thousand Trimmy users have ten thousand different exchange keys; the schema admits one.
2. **On mainnet the allow-list has exactly one entry** (`Ignite`). `PublicWeb2` — the unrestricted, any-host source — is explicitly commented *"Only available on testnets."* So even a demo built on `PublicWeb2` has no mainnet path.
3. **Anything reachable via `PublicWeb2` is by construction public.** If a Trimmy user put their own key in the `headers` request field, that field is part of the attestation request, is submitted on-chain, and is fetched independently by every participating data provider. The key would be disclosed to the whole provider set and to any chain observer.

Point 1 is the strongest and is the one to lead with: **it is a schema-level impossibility, not a privacy tradeoff.**

`[Unverified]` I did not independently confirm the "~100 providers" figure, nor did I confirm by transaction trace that the `headers` field is written to calldata on the attestation request. Experiment to settle: submit a Web2Json attestation request on Coston2 via `FdcHub.requestAttestation` with a sentinel header value, then `cast tx <hash>` and grep the calldata for the sentinel. I recommend either running that or dropping the "headers go on-chain" phrasing in favour of point 1, which is already fully verified.

### 1.3 What this means for the Bounty 2 pitch

The one-liner: *"FDC Web2Json can attest public web data, and exactly one pre-negotiated partner API. It structurally cannot attest **your** account at **your** provider, because the credential lives in the verifier operator's environment, not the user's. FCC can — because the credential lives inside an enclave whose code hash is on-chain, and the user hands it over directly."*

That is a clean, verifiable, non-overlapping justification for why Trimmy needs FCC and not FDC.

---

## 2. Real structure of the scaffold (code, quoted)

### 2.1 Instruction lifecycle

`[Verified]` from `fce-extension-scaffold` + `tee-node/docs/extensions.md`:

```
1. Caller → your InstructionSender contract (on-chain, payable)
2. InstructionSender → TeeExtensionRegistry.sendInstructions(teeIds, params) → emits TeeInstructionsSent
3. ext-proxy watches the Flare C-chain indexer DB, picks up the instruction
4. tee-node (inside the enclave) pulls the action from the proxy
5. tee-node → POST http://localhost:${EXTENSION_PORT}/action  (your Go/Py/TS server)
6. your handler decodes → validates → executes → returns ActionResult
7. tee-node signs the ActionResult with the TEE key, posts it to the proxy
8. caller polls GET ${EXT_PROXY_URL}/action/result/{actionId}
```

### 2.2 `TeeExtensionRegistry` — the only entry point

`[Verified]` `contracts/interfaces/ITeeExtensionRegistry.sol`:

```solidity
interface ITeeExtensionRegistry {
    struct TeeInstructionParams {
        bytes32 opType;
        bytes32 opCommand;
        bytes message;
        address[] cosigners;
        uint64 cosignersThreshold;
        address claimBackAddress;
    }

    function sendInstructions(
        address[] calldata _teeIds,
        TeeInstructionParams calldata _instructionParams
    ) external payable returns (bytes32 _instructionId);

    function nextPublicExtensionId() external view returns (uint256);

    function getTeeExtensionInstructionsSender(uint256 _extensionId)
        external view returns (address);
}
```

Access control: registration binds the extension to exactly one InstructionSender address; the registry rejects `sendInstructions` from any other `msg.sender`. `[Verified]` — described in `docs/instruction-sender.md` and enforced by `register-extension` taking `--instructionSender`.

### 2.3 The InstructionSender pattern

`[Verified]` `contracts/InstructionSender.sol`. The load-bearing parts:

```solidity
bytes32 public constant OP_TYPE_GREETING      = bytes32("GREETING");
bytes32 public constant OP_COMMAND_SAY_HELLO  = bytes32("SAY_HELLO");
bytes32 public constant OP_COMMAND_SAY_GOODBYE= bytes32("SAY_GOODBYE");

uint256 private constant FIRST_PUBLIC_EXTENSION_ID = 0x10000; // 65536

function setExtensionId() external {
    require(_extensionId == 0, "Extension ID already set.");
    uint256 c = TEE_EXTENSION_REGISTRY.nextPublicExtensionId();
    for (uint256 i = FIRST_PUBLIC_EXTENSION_ID; i < c; ++i) {
        if (TEE_EXTENSION_REGISTRY.getTeeExtensionInstructionsSender(i) == address(this)) {
            _extensionId = i;
            return;
        }
    }
    revert("Extension ID not found.");
}

function sendSayHello(bytes calldata _message) external payable {
    address[] memory teeIds = TEE_MACHINE_REGISTRY.getRandomTeeIds(_getExtensionId(), 1);
    address[] memory cosigners = new address[](0);
    ITeeExtensionRegistry.TeeInstructionParams memory params = ITeeExtensionRegistry.TeeInstructionParams({
        opType: OP_TYPE_GREETING,
        opCommand: OP_COMMAND_SAY_HELLO,
        message: _message,
        cosigners: cosigners,
        cosignersThreshold: 0,
        claimBackAddress: msg.sender
    });
    TEE_EXTENSION_REGISTRY.sendInstructions{value: msg.value}(teeIds, params);
}
```

Note the two message encodings the scaffold deliberately demonstrates: `sendSayHello` passes **raw JSON bytes**; `sendSayGoodbye` passes `abi.encode(SayGoodbyeMessage{...})`. Both are legal; the handler must decode with the matching decoder.

### 2.4 OPType / OPCommand routing — the three layers

`[Verified]` The identifiers must match byte-for-byte across three files:

| Layer | File | Form |
|---|---|---|
| Solidity | `contracts/InstructionSender.sol` | `bytes32("GREETING")` |
| Go config | `go/internal/config/config.go` | `OPTypeGreeting = "GREETING"` |
| Go router | `go/internal/extension/extension.go` | `dataFixed.OPType == teeutils.ToHash(config.OPTypeGreeting)` |

`bytes32(string)` in Solidity and `teeutils.ToHash(string)` in Go are the same operation: UTF-8 bytes, left-aligned, right zero-padded to 32. Identifiers are therefore capped at 32 bytes. `[Verified]` — `go-flare-common/pkg/tee/op/op.go`:

```go
func toHash(s string) common.Hash {
	b := []byte(s)
	if len(b) > 32 {
		panic("op: identifier too long for 32-byte hash: " + s)
	}
	var h common.Hash
	copy(h[:], b)
	return h
}
```

> The scaffold README says 31 bytes in places; the code says 32. Use ≤ 31 to be safe against the discrepancy. `[Verified]` code path is 32.

**Naming constraint (important, easy to trip over).** `[Verified]` `go-flare-common/pkg/tee/op/op.go`:

```go
func IsValid(t Type, c Command) bool {
	if t.IsSystem() {
		return validSystemPairs[t][c]
	}
	return !t.isF()          // isF() == strings.HasPrefix(t, "F_")
}
```

Any OPType **not** beginning with `F_` is valid with any OPCommand. Reserved system prefixes are `F_REG`, `F_WALLET`, `F_GET`, `F_POLICY`, `F_GOVERNANCE`, `F_XRP`, `F_BTC`, `F_FDC2`. **Trimmy must not name an OPType starting with `F_`.** `TRIMMY` is fine.

### 2.5 The Go action handler shape

`[Verified]` `go/internal/extension/extension.go`. Two-level switch, then a 4-step handler:

```go
func (e *Extension) processAction(action teetypes.Action) (int, []byte) {
	dataFixed, err := processorutils.Parse[instruction.DataFixed](action.Data.Message)
	if err != nil {
		return http.StatusBadRequest, []byte(fmt.Sprintf("decoding fixed data: %v", err))
	}
	switch {
	case dataFixed.OPType == teeutils.ToHash(config.OPTypeGreeting):
		return e.processGreeting(action, dataFixed)
	default:
		return http.StatusNotImplemented, []byte(/* unsupported op type … */)
	}
}
```

and the handler contract — decode, validate, execute, build:

```go
func (e *Extension) processSayHello(action teetypes.Action, df *instruction.DataFixed) teetypes.ActionResult {
	var req types.SayHelloRequest
	dec := json.NewDecoder(bytes.NewReader(df.OriginalMessage))
	dec.DisallowUnknownFields()                       // 1. DECODE strictly
	if err := dec.Decode(&req); err != nil {
		return buildResult(action, df, nil, 0, fmt.Errorf("decoding request: %w", err))
	}
	if req.Name == "" {                               // 2. VALIDATE — untrusted input
		return buildResult(action, df, nil, 0, fmt.Errorf("name must not be empty"))
	}
	e.mu.Lock(); e.greetingCount++; /* … */ e.mu.Unlock()   // 3. EXECUTE
	data, _ := json.Marshal(resp)
	return buildResult(action, df, data, 1, nil)      // 4. BUILD (status 1 = success)
}
```

`[Verified]` `go/internal/extension/utils.go` — the result envelope and the status contract:

```go
func buildResult(a teetypes.Action, df *instruction.DataFixed, data []byte, status uint8, err error) teetypes.ActionResult {
	ar := teetypes.ActionResult{
		ID:            a.Data.ID,
		SubmissionTag: a.Data.SubmissionTag,
		Version:       config.Version,
		OPType:        df.OPType,
		OPCommand:     df.OPCommand,
		Data:          data,
		Status:        status,
	}
	switch status {
	case 0:  ar.Log = fmt.Sprintf("error: %v", err)
	case 1:  ar.Log = "ok"
	default: ar.Log = "pending"
	}
	return ar
}
```

Status semantics: `0` = error, `1` = success, `>= 2` = pending/async. `[Verified]`

### 2.6 The ActionResult hash — what the TEE actually signs

This is the single most important detail for any contract that consumes a TEE result. `[Verified]` `tee-node/pkg/types/actions.go`:

```go
// Hash returns keccak256(keccak256(data) || id || keccak256(submissionTag) || status).
func (ar *ActionResult) Hash() []byte {
	dataHash := crypto.Keccak256(ar.Data)
	tagHash  := crypto.Keccak256([]byte(ar.SubmissionTag))
	packed := make([]byte, 0, 32+32+32+1)
	packed = append(packed, dataHash...)
	packed = append(packed, ar.ID[:]...)
	packed = append(packed, tagHash...)
	packed = append(packed, ar.Status)
	return crypto.Keccak256(packed)
}
```

The node does **not** sign `Hash()` directly. It signs a domain-separated, chain-bound wrapper. `[Verified]` from the Solidity side in `fce-weather-insurance/contracts/InstructionSender.sol`:

```solidity
bytes32 private constant TEE_ACTION_RESULT_PREFIX = bytes32("TEE_ACTION_RESULT");

bytes32 resultHash = keccak256(abi.encodePacked(
    keccak256(_resultData), _actionId, keccak256(bytes(_submissionTag)), _status));

// The TEE node signs a domain-separated payload over resultHash, not resultHash
// directly — see TEE_ACTION_RESULT_PREFIX above.
bytes32 payloadHash = keccak256(abi.encode(TEE_ACTION_RESULT_PREFIX, block.chainid, resultHash));

address signer = _recover(_ethSigned(payloadHash), _signature);  // EIP-191 personal_sign
require(signer == teeAddress, "bad TEE signature");
```

**Now verified from the Go side too**, which is what actually matters — the Solidity above is only a claim *about* the node. `[Verified]` `go-flare-common/pkg/signing/hash.go`:

```go
// Payload is the Go representation of the Solidity Payload struct.
//	struct Payload { bytes32 prefix; uint256 chainId; bytes32 dataHash; }
type Payload struct {
	Prefix   [32]byte `abi:"prefix"`
	ChainID  *big.Int `abi:"chainId"`
	DataHash [32]byte `abi:"dataHash"`
}

// Hash ABI-encodes the payload and returns its keccak256 hash.
func (p Payload) Hash() ([32]byte, error) {
	encoded, err := abicoder.Encode(PayloadArgument, p)   // PayloadArgument is a *tuple* type
	...
	return crypto.Keccak256Hash(encoded), nil
}
```

`[Verified]` `go-flare-common/pkg/signing/prefixes.go`: `TEEActionResult Prefix = mustStringBytes32("TEE_ACTION_RESULT")`.

`[Verified]` And the actual signing site, `tee-node/internal/processors/instructions/signutils/processor.go:158`:

```go
signHash, err := csigning.NewPayload(csigning.TEEActionResult, chainID, common.BytesToHash(result.Hash())).Hash()
sig, err := p.Sign(signHash[:])
```

where `Sign` applies EIP-191 `[Verified]` (`go-flare-common/pkg/tee/signer/signer.go:318`: `toSign := accounts.TextHash(hash[:])`).

`[Inference]` The Go side encodes a **static 3-field tuple**; Solidity's `abi.encode(bytes32, uint256, bytes32)` produces the identical 96 bytes, because a tuple of only static types is encoded inline with no offset word. So the Solidity reconstruction in §2.6 is byte-exact against the Go signer. This is why both forms are correct and interchangeable.

#### ⚠ The two-signature footgun (new — not documented anywhere upstream)

`[Verified]` `tee-node/pkg/types/actions.go` — an `ActionResponse` carries **two different signatures by two different keys under two different domains**:

```go
type ActionResponse struct {
	Result         ActionResult  `json:"result"`
	Signature      hexutil.Bytes `json:"signature"`        // TEE node key,  TEE_ACTION_RESULT domain
	ProxySignature hexutil.Bytes `json:"proxySignature"`   // ext-proxy key, PROXY_ACTION_RESULT domain
}
```

The proxy signs with `csigning.ProxyActionResult` `[Verified]` (`tee-proxy/internal/server/external.go:286`), the node with `csigning.TEEActionResult` `[Verified]`. **A contract verifying against `teeAddress` must consume `result.signature`, never `result.proxySignature`** — they recover to different addresses under different preimages. `GET /action/result/{id}` returns both in one JSON object, so this is very easy to get wrong.

Upstream has a regression test asserting the bare-hash path must fail `[Verified]` (`tee-proxy/internal/server/external_test.go:83-94`):

```go
legacyHash := accounts.TextHash(got.Result.Hash())
legacyPub, err := crypto.SigToPub(legacyHash, got.ProxySignature)
if err == nil {
	assert.NotEqual(t, proxyAddr, crypto.PubkeyToAddress(*legacyPub),
		"ProxySignature must NOT recover under the bare (undomained) Result.Hash() path")
}
```

That test exists because the bare-`Hash()` scheme is a *legacy* scheme that was removed. Any tutorial or LLM-generated snippet predating the change will verify against `Result.Hash()` and silently never match.

Four things a naive implementation gets wrong and that cost hours:
1. Verifying against `resultHash` instead of `payloadHash` — fails (this is the removed legacy scheme).
2. Verifying `proxySignature` instead of `signature` — recovers a valid-looking but *wrong* address.
3. Forgetting the EIP-191 `\x19Ethereum Signed Message:\n32` prefix (`_ethSigned`) — fails.
4. Forgetting `block.chainid` is inside the payload — signatures do not port between Coston2 (114) and mainnet.

Only `status == 1` results should be accepted on-chain. `[Verified]` — the weather contract requires it. Note statuses `3, 4, 5…` are used by upstream for *streamed partial* results `[Verified]` (`signutils/processor.go`: `status = 3 + uint8(i)` for all but the last entry), so "status >= 2 means pending" must be treated as "not final", not as an error.

### 2.6b The synchronous budget is **2 seconds** — this is a hard architectural constraint

This resolves what was the single largest open question in this design, and it is the fact most likely to break a naive Trimmy implementation.

`[Verified]` `tee-node/internal/extension/extension.go` — the node calls your extension with an `http.Client` whose timeout is a compile-time constant:

```go
// PostActionToExtension sends POST request with response in body to url.
func PostActionToExtension(url string, action *types.Action) (*types.ActionResult, error) {
	client := http.Client{
		Timeout: settings.ProxyTimeout,
	}
	...
	res, err := client.Post(url, "application/json", bytes.NewReader(requestBody))
```

`[Verified]` `tee-node/internal/settings/settings.go`:

```go
const ProxyTimeout = 2 * time.Second

// ActionProcessTimeout bounds the synchronous per-action processing time.
// When exceeded the action's context is cancelled so cancellation-aware
// processors short-circuit before committing state.
var ActionProcessTimeout = 10 * time.Second

// ActionDrainTimeout bounds how long the queue worker waits for an in-flight ...
var ActionDrainTimeout = 5 * time.Second
```

Three separate budgets, and the tightest one governs the handler:

| Constant | Value | Bounds | Configurable? |
|---|---|---|---|
| `ProxyTimeout` | **2 s** | the `POST /action` HTTP call into your extension | **No** — `const` |
| `ActionProcessTimeout` | 10 s | total synchronous per-action processing in the node | `var` (tests only) |
| `ActionDrainTimeout` | 5 s | queue-worker wait for an in-flight action on shutdown | `var` (tests only) |

**Consequence for Trimmy, stated plainly.** `[Inference]` from the above: a handler that performs an outbound TLS REST call to a third-party exchange **cannot** reliably complete inside 2 s. A cold TLS handshake to `api.kraken.com` plus a signed private-endpoint round trip is routinely 300–900 ms and has a long tail well past 2 s under rate limiting or packet loss. The 2 s budget is a `const`, so we cannot raise it without forking `tee-node` — and forking it changes the code hash, which would have to be re-whitelisted.

**Therefore `EVAL` must be asynchronous, by design, not as a fallback.** The handler must:

1. Return **immediately** (well inside 2 s) with `status >= 2` (pending) and no signature.
2. Continue the fetch on a background goroutine.
3. When the fetch completes, build the final `ActionResult` with `status == 1`, sign it via the sign port, and `POST` it to `${PROXY_URL}/result` itself.

That is exactly the shape upstream uses for its own multi-step signing flow `[Verified]` (`signutils/processor.go` builds the result, computes `csigning.NewPayload(TEEActionResult, …)`, signs, then `queue.PostActionResponse(proxyURL+"/result", response)`), and it is why `fce-weather-insurance` had to make settlement async. **Do not attempt a synchronous `EVAL`.** Budget a full day for this in the plan.

`PROBE` (§5.4) is the exception: it may stay synchronous **only** if it reads a cached value already in enclave memory, never if it performs a network fetch.

### 2.7 The types server

`[Verified]` `fce-weather-insurance` ships it (`internal/typesserver/server.go`, `pkg/decoder/`, `pkg/types/register.go`); the scaffold does **not** — it has no `pkg/decoder` and no `register.go`. If Trimmy wants a types server we port it from weather-insurance.

Registration is per `(OPType, OPCommand, Kind)`:

```go
func RegisterDecoders(r *decoder.Registry) {
	r.Register(
		decoder.RegistryKey{OPType: "WEATHER", OPCommand: "FETCH", Kind: decoder.KindMessage},
		decoder.NewABIDecoder[GetWeatherRequest](GetWeatherMessageArg),
	)
	r.Register(
		decoder.RegistryKey{OPType: "WEATHER", OPCommand: "FETCH", Kind: decoder.KindResult},
		decoder.NewJSONDecoder[WeatherReport](),
	)
	// BUY message is ECIES ciphertext on-chain; report opaque bytes
	r.Register(
		decoder.RegistryKey{OPType: "WEATHER", OPCommand: "BUY", Kind: decoder.KindMessage},
		encryptedMessageDecoder{},
	)
}
```

Default port `8100`, endpoints `POST /decode`, `GET /registry`, `GET /health`. `[Verified]` `internal/config/config.go` (`TypesServerPort = 8100`).

The `encryptedMessageDecoder` is a good pattern for Trimmy: for any command whose on-chain message is ciphertext, register a decoder that reports `{encrypted: true, length, hex}` rather than pretending to decode it.

---

## 3. Scaffold defects — verification and patches

### 3.1 Summary table

| # | Defect | Reported by | Verdict | Severity |
|---|---|---|---|---|
| a | `tee-node` pinned below minimum in `go/go.mod` + `tools/go.mod` | participant | **Confirmed, and worse than reported** | High (security) |
| b | `post-build.sh` calls `register-tee` without `-command rRap` | participant | **Confirmed** | High (blocks deploy) |
| c | `extension_proxy.coston2.docker.toml` ships only as `.example` | participant | **Confirmed** | Medium (confusing failure) |
| d | `pre-build.sh` has no `--force` guard; re-mints a new extension every run | **new — mine** | **Confirmed** | High (bricks the deploy) |
| e | `privateBuyResultDecoder` length check is stale (`!= 6` vs 8 args) | **new — mine** | Confirmed by reading; not executed | Low (weather repo only) |
| f | `setExtensionId()` is O(n) over all public extensions | **new — mine** | Confirmed, currently tolerable | Low (watch item) |

---

### 3.2 Defect (a) — `tee-node` version pin

**Confirmed, and the participant understated it.** `[Verified]`

Both module files pin the identical pseudo-version:

```
# go/go.mod line 8, tools/go.mod line 8
github.com/flare-foundation/tee-node v0.0.21-0.20260619120252-31fc839ae6d2
```

`fce-weather-insurance/go.mod:8` and `fce-weather-insurance/tools/go.mod:8` carry the same pin. `[Verified]`

**The subtlety worth writing up in the PR.** I queried the Go module proxy: `[Verified]`

```
$ curl -s https://proxy.golang.org/github.com/flare-foundation/tee-node/@v/v0.0.21.info
{"Version":"v0.0.21","Time":"2026-06-19T12:02:52Z","Origin":{...,"Hash":"31fc839ae6d22e3ff403573a832e6eddcb300fc2","Ref":"refs/tags/v0.0.21"}}
```

The pinned pseudo-version's embedded timestamp (`20260619120252`) and commit prefix (`31fc839ae6d2`) are **exactly tag `v0.0.21`**. But by Go's pseudo-version grammar, `vX.Y.Z-0.<ts>-<sha>` has base version `vX.Y.(Z-1)` — so `v0.0.21-0.…` **sorts below `v0.0.21`**. The pin is byte-identical code to `v0.0.21` wearing a version string that orders lower. Anyone reading the file assumes "v0.0.21-ish"; MVS treats it as pre-v0.0.21.

**Available versions** (`proxy.golang.org/.../@v/list`, sorted): `v0.0.15 … v0.0.21, v0.0.22, v0.0.23, v0.0.24, v0.0.25`. `@latest` is **`v0.0.25`**, tagged 2026-08-05 — *one day before this doc*. `[Verified]`

The participant said "bump to v0.0.24". **v0.0.25 now exists** and should be the target.

**Why this is a security bump, not a housekeeping bump.** I diffed `v0.0.21..v0.0.25` and mapped each fix to its first containing tag with `git tag --contains`: `[Verified]`

| Commit | First tag | Subject |
|---|---|---|
| `6b35685` | **v0.0.23** | `fix: bind sign/decrypt server to loopback` |
| `aa5fb74` | **v0.0.23** | `fix: reject non-canonical (high-S) ECDSA signatures` |
| `468c83c` | **v0.0.23** | `fix: validate inner teeId in KEY_DELETE against local TEE identity` |
| `76a4e3e` | **v0.0.23** | `Audit fixes: rework restore authorization for data-provider and direct backup restore` |
| `3c87781` | **v0.0.23** | `Support Safe-backed governance for machine path list approval` |

The loopback fix in particular is severe, and its own commit message says so:

```
fix: bind sign/decrypt server to loopback

The sign/decrypt API is unauthenticated and relies on the shared TEE
boundary, but NewSignServer bound to :SIGN_PORT (all interfaces), so any
network peer or colocated process able to reach the port could use active
wallet and TEE keys as arbitrary signing/decryption oracles.
```

**This is directly load-bearing for Trimmy.** Our extension will hold user exchange credentials and call `POST /decrypt` on the sign port. On the pinned version, that port binds `0.0.0.0`. Shipping Trimmy on the scaffold's default pin would expose the TEE key as a decryption oracle to anything that can route to the container. **We must bump regardless of whether upstream accepts the PR.**

`[Verified]` I confirmed the fixed state in the current `tee-node` tree — the binding is now a `const`, with the rationale in the code, and the routes it protects are exactly the ones we depend on:

```go
// tee-node/internal/settings/settings.go
// SignHost is the interface the sign/decrypt server binds to. It is fixed to
// loopback so the unauthenticated sign/decrypt API is reachable only from
// within the TEE instance, per the security model. It is intentionally not
// configurable.
const SignHost = "127.0.0.1"
```

```go
// tee-node/internal/extension/server/server.go
func NewSignServer(port int, ...) *SignServer {
	// Bind to loopback: the sign/decrypt API is unauthenticated and relies on
	// the shared TEE boundary, so it must not listen on all interfaces.
	addr := net.JoinHostPort(settings.SignHost, strconv.Itoa(port))
```

and the decrypt routes themselves `[Verified]` (`server.go:89-90`):

```go
mux.HandleFunc(fmt.Sprintf("POST /decrypt/{%s}/{%s}", walletID, keyID), s.decryptWithKeyHandler)
mux.HandleFunc("POST /decrypt", s.decryptWithTeeHandler)
```

`POST /decrypt` (the TEE-key variant) is the endpoint Trimmy's `CRED_PUT` calls. **The API is unauthenticated by design** — its only defence is the loopback bind. That makes the version bump non-negotiable for us: on the pinned build, anything that can reach the container's sign port can decrypt every user credential we hold.

**Patch.**

```diff
--- a/go/go.mod
+++ b/go/go.mod
@@ -6,7 +6,7 @@ require (
 	github.com/ethereum/go-ethereum v1.17.4
 	github.com/flare-foundation/go-flare-common v1.2.2-0.20260623111601-c573c79c0924
-	github.com/flare-foundation/tee-node v0.0.21-0.20260619120252-31fc839ae6d2
+	github.com/flare-foundation/tee-node v0.0.25
 	github.com/joho/godotenv v1.5.1
 )
```

```diff
--- a/tools/go.mod
+++ b/tools/go.mod
@@ -6,7 +6,7 @@ require (
 	github.com/ethereum/go-ethereum v1.17.4
 	github.com/flare-foundation/go-flare-common v1.2.2-0.20260623111601-c573c79c0924
-	github.com/flare-foundation/tee-node v0.0.21-0.20260619120252-31fc839ae6d2
+	github.com/flare-foundation/tee-node v0.0.25
 	github.com/flare-foundation/tee-proxy v0.0.18
 	github.com/joho/godotenv v1.5.1
 	github.com/pkg/errors v0.9.1
 )
```

Then, in this order:

```bash
(cd go && go mod tidy && go build ./... && go vet ./...)
(cd tools && go mod tidy && go build ./... && go vet ./... && go test ./...)
./scripts/check-versions.sh     # must report "all version pins consistent"
```

**Two consequences the PR must call out.**

1. `scripts/lib/versions.sh` derives `TEE_NODE_REF` from the pin, and it handles a plain tag correctly — I read the function: `[Verified]`

   ```bash
   _versions_ref() {
       local version="$1"
       if [[ "$version" =~ [0-9]{14}-([0-9a-f]{12})$ ]]; then
           echo "${BASH_REMATCH[1]}"     # pseudo-version → commit SHA
       else
           echo "$version"               # plain tag → the tag
       fi
   }
   ```
   After the bump, `TEE_NODE_REF=v0.0.25` (a tag), which `docker/node-base.Dockerfile` clones. This is *better* than before — a tag is more legible than an abbreviated SHA. No change needed there.

2. `scripts/check-versions.sh` only enforces **consistency** between `go/go.mod` and `tools/go.mod`; it has **no minimum-version floor**. `[Verified]` — I read the whole script; it does three cross-checks and zero version comparisons. **The "v0.0.22 minimum" the participant cites is not enforced anywhere in this repo, and I could not find its source.** `[Unverified]` — the claim that v0.0.22 is a hard minimum. Experiment to settle: ask in the hackathon Telegram, or attempt `register-tee` against Coston2 with the v0.0.21 pin and observe whether the FTDC availability check rejects the code hash. Regardless, the v0.0.23 audit fixes justify the bump on their own merits, so the PR should be argued from those, not from an unverified floor.

   **Bonus improvement worth including in the PR:** add a floor to `check-versions.sh` so this cannot regress. Sketch:

   ```bash
   # --- 5. tee-node must be at or above the security floor (v0.0.23 audit fixes) ---
   TEE_NODE_MIN="v0.0.23"
   if [[ "$(printf '%s\n%s\n' "$TEE_NODE_MIN" "$EXT_NODE" | sort -V | head -1)" != "$TEE_NODE_MIN" ]]; then
       echo -e "${RED}  tee-node $EXT_NODE is below the $TEE_NODE_MIN security floor${NC}" >&2
       echo "    v0.0.23 binds the sign/decrypt server to loopback and rejects high-S signatures." >&2
       FAILED=1
   fi
   ```
   (Note `sort -V` orders `v0.0.21-0.2026…` before `v0.0.21`, which is the desired behaviour here.)

---

### 3.3 Defect (b) — `register-tee` missing `-command rRap`

**Confirmed.** `[Verified]`

The flag default in `tools/cmd/register-tee/main.go`:

```go
command := flag.String("command", "rap", "command (rap)")
```

And `scripts/post-build.sh` Step 3 invokes it **without** `-command`:

```bash
go run ./cmd/register-tee \
    -a "$ADDRESSES_FILE" \
    -c "$CHAIN_URL" \
    -p "$EXT_PROXY_URL" \
    -h "${EXT_PROXY_HOST_URL:-$EXT_PROXY_URL}" \
    -ep "$NORMAL_PROXY_URL" \
    -state "$PROJECT_DIR/config/register-tee.state" \
    || die "Register TEE failed"
```

So `command` = `"rap"`.

**Why `rap` breaks on re-run.** `[Verified]` `tools/pkg/fccutils/registration.go`. The command string is a set of step letters matched with `strings.Contains`:

| Letter | Step |
|---|---|
| `r` | pre-registration (`register()`), **or**, if already registered, request a fresh attestation |
| `R` | request a fresh TEE attestation unconditionally |
| `a` | FTDC availability check |
| `p` | promote to production (`toProduction`) |

The `r` branch already contains a re-run guard:

```go
machineInfo, machineErr := s.TeeMachineRegistry.GetTeeMachine(callOpts, teeID)
if machineErr == nil && machineInfo.TeeId != (common.Address{}) {
    // Already registered (e.g. a re-run): skip machine pre-registration,
    // but the original attestation challenge is one-shot and may have
    // expired, so request a FRESH attestation to get a valid challenge —
    // otherwise the availability check below reverts with ChallengeExpired.
    logger.Infof("TEE machine %s already registered on-chain, requesting fresh attestation", teeID.Hex())
    teeAttestInstructionID, err = RequestTeeAttestation(s, teeID)
```

**But that guard is defeated by the state file.** The very first line of the `r` branch is:

```go
if strings.Contains(state.CompletedSteps, "r") {
    logger.Infof("Pre-registration already completed, skipping (from state file)")
    teeAttestInstructionID = state.TeeAttestInstructionID     // ← STALE challenge
}
```

`[Inference]`, from the two quoted blocks: if a prior run completed `r` and then failed at `a` or `p`, the state file records `"r"`. On resume, `r` is skipped entirely and the **stale** `teeAttestInstructionID` is reused. The attestation challenge is one-shot, so the availability check reverts `Verification.ChallengeExpired`. Adding `R` forces an unconditional fresh attestation and breaks the loop.

There is a second trigger with no state file at all: `register-tee` deletes the state file unless `--resume` is passed, so a clean re-run takes the "already registered → fresh attestation" path and *is* fine. The failure is specific to the resume path and to any case where the machine is registered but the state file survives. `[Inference]` from the same code.

**Patch.**

```diff
--- a/scripts/post-build.sh
+++ b/scripts/post-build.sh
@@ -/- Step 3: Register TEE on-chain ---
 step 3 "Register TEE machine"
 go run ./cmd/register-tee \
     -a "$ADDRESSES_FILE" \
     -c "$CHAIN_URL" \
     -p "$EXT_PROXY_URL" \
     -h "${EXT_PROXY_HOST_URL:-$EXT_PROXY_URL}" \
     -ep "$NORMAL_PROXY_URL" \
+    -command "${REGISTER_TEE_COMMAND:-rRap}" \
     -state "$PROJECT_DIR/config/register-tee.state" \
     || die "Register TEE failed"
```

Also worth fixing the misleading flag help, which documents only one legal value:

```diff
--- a/tools/cmd/register-tee/main.go
+++ b/tools/cmd/register-tee/main.go
-	command := flag.String("command", "rap", "command (rap)")
+	// Step letters, applied in order: r=pre-register (or refresh attestation if
+	// already registered), R=force fresh attestation, a=FTDC availability check,
+	// p=promote to production. Default rRap is re-run safe: R guarantees a fresh
+	// one-shot challenge, avoiding Verification.ChallengeExpired on resume.
+	command := flag.String("command", "rRap", "registration steps: any subset of r,R,a,p in order")
```

And document `REGISTER_TEE_COMMAND` in the `post-build.sh` header comment block alongside the other env inputs.

---

### 3.4 Defect (c) — missing `extension_proxy.coston2.docker.toml`

**Confirmed.** `[Verified]`

The repo ships only the template:

```
config/proxy/extension_proxy.coston2.docker.toml.example
```

`.gitignore` deliberately excludes the real file (it holds DB credentials):

```
# Coston/Coston2 proxy configs (contain DB credentials)
config/proxy/extension_proxy.coston.toml
config/proxy/extension_proxy.coston.docker.toml
config/proxy/extension_proxy.coston2.toml
config/proxy/extension_proxy.coston2.docker.toml
```

But `docker-compose.coston2.yaml` bind-mounts it unconditionally:

```yaml
services:
  ext-proxy:
    volumes:
      - ./config/proxy/extension_proxy.coston2.docker.toml:/app/config/config.toml:ro
```

Docker's bind-mount semantics create a **directory** at a missing source path, then fail mounting a directory onto a file. `[Verified]` — and upstream has already *documented* this exact failure for the Coston variant, in `fce-sign/SCAFFOLD_SYNC_UPDATE.md` §7:

```
error mounting ".../extension_proxy.coston.docker.toml" ... cannot create
subdirectories ... not a directory: Are you trying to mount a directory onto a
file (or vice-versa)?

Root cause: with the file missing, Docker auto-created an empty **directory** at
that path and then couldn't mount a directory onto the `/app/config/config.toml`
file.
```

So the root cause is known to the Flare team; what is missing is a **guard in the scaffold**. `start-services.sh` runs `docker compose up -d --build` with no pre-check — I read the whole script and there is no test for the config file's existence. `[Verified]`

**Patch** — fail fast with an actionable message, in `scripts/start-services.sh`, immediately before the `COMPOSE_FILES` case block:

```diff
--- a/scripts/start-services.sh
+++ b/scripts/start-services.sh
@@ (before: case "$CHAIN" in local) ;; coston) … )
+    # --- Guard: chain overlays bind-mount a gitignored proxy config ---
+    # The .toml holds indexer DB credentials and is deliberately not committed.
+    # If it is missing, Docker silently creates a DIRECTORY at that path and then
+    # fails with an opaque "cannot create subdirectories / not a directory" rootfs
+    # mount error. Check first and print the one command that fixes it.
+    if [[ "$CHAIN" == "coston" || "$CHAIN" == "coston2" ]]; then
+        PROXY_CFG="$PROJECT_DIR/config/proxy/extension_proxy.$CHAIN.docker.toml"
+        if [[ -d "$PROXY_CFG" ]]; then
+            log "Removing stray directory left by a previous failed mount: $PROXY_CFG"
+            rmdir "$PROXY_CFG" 2>/dev/null || die "Remove the directory at $PROXY_CFG manually, then re-run."
+        fi
+        if [[ ! -f "$PROXY_CFG" ]]; then
+            die "Missing proxy config: $PROXY_CFG
+  This file is gitignored because it holds indexer DB credentials.
+  Create it from the template and fill in the [db] block:
+
+    cp $PROXY_CFG.example $PROXY_CFG
+
+  Coston2 indexer: host 34.38.42.208, port 3306, database \"indexer\".
+  Credentials are issued via https://flare.network/resources/technical-support"
+        fi
+    fi
+
     case "$CHAIN" in
```

The `rmdir` branch matters: once a user has hit this once, the stray directory persists and every subsequent run fails the same way even after they create the file — because the path is now a directory. Cleaning it up is what turns this from "confusing" into "self-healing".

---

### 3.5 Defect (d) — `pre-build.sh` re-mints an extension on every run *(new)*

**Confirmed, and I rate this the most dangerous of the six for a hackathon team.** `[Verified]`

`fce-sign/scripts/pre-build.sh` has an explicit guard:

```
75:# --- Guard: refuse to clobber an existing extension config ---
83:    [[ "$arg" == "--force" ]] && FORCE=1
89:    # A valid extension.env already exists. Re-minting here would orphan any TEE
94:    log "$CONFIG_OUTPUT already exists — reusing it (skipping mint)."
100:    echo "    PRE_BUILD_FORCE=1 ./scripts/pre-build.sh    # or: ./scripts/pre-build.sh --force"
```

`fce-extension-scaffold/scripts/pre-build.sh` has **none**. I grepped for `force`: zero matches. `[Verified]` It parses no arguments at all, and unconditionally runs Step 2 (deploy a new `InstructionSender`) and Step 3 (register a new extension), then overwrites `config/extension.env`.

**Consequence.** `[Inference]`, from the guard comment quoted above plus the documented `MachineManager.TooMany()` failure mode: a second `./scripts/pre-build.sh` — which is a completely natural thing to do after any earlier step fails — mints a fresh `EXTENSION_ID`, orphans the TEE machine registered under the previous one, and the next `post-build.sh` reverts with `MachineManager.TooMany()`. On-chain state cannot be rolled back. It also burns C2FLR on a wasted deploy each time.

This is a straight regression against `fce-sign`, which makes it very easy to argue in a PR: **port the guard the sibling repo already has.**

**Patch** — insert after the `.env` load block in `scripts/pre-build.sh`:

```bash
# --- Guard: refuse to clobber an existing extension config ---
# Re-minting orphans any TEE machine registered under the previous EXTENSION_ID
# and makes the next post-build revert with MachineManager.TooMany(). On-chain
# state cannot be rolled back, so default to reuse and require an explicit opt-in.
FORCE="${PRE_BUILD_FORCE:-0}"
for arg in "$@"; do
    [[ "$arg" == "--force" ]] && FORCE=1
done

if [[ -f "$CONFIG_OUTPUT" && "$FORCE" != "1" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_OUTPUT"
    if [[ -n "${EXTENSION_ID:-}" && -n "${INSTRUCTION_SENDER:-}" ]]; then
        log "$CONFIG_OUTPUT already exists — reusing it (skipping mint)."
        log "  EXTENSION_ID        $EXTENSION_ID"
        log "  INSTRUCTION_SENDER  $INSTRUCTION_SENDER"
        echo ""
        echo "  To mint a fresh extension + InstructionSender (e.g. after a diamond redeploy),"
        echo "  re-run with:"
        echo "    ./scripts/pre-build.sh --force     # or: PRE_BUILD_FORCE=1 ./scripts/pre-build.sh"
        exit 0
    fi
    log "$CONFIG_OUTPUT exists but is incomplete — re-minting."
fi
```

---

### 3.6 Defect (e) — stale decoder length check in `fce-weather-insurance` *(new)*

`[Verified by reading; not executed]` `fce-weather-insurance/pkg/types/register.go`:

```go
type privateBuyResultDecoder struct{}

func (privateBuyResultDecoder) Decode(data []byte) (any, error) {
	vals, err := PrivateBuyResultArgs.Unpack(data)
	if err != nil { return nil, err }
	if len(vals) != 6 {
		return nil, fmt.Errorf("expected 6 values, got %d", len(vals))
	}
	return PrivateBuyResult{ /* reads vals[0..5] */ }, nil
}
```

But `PrivateBuyResultArgs` is built with **eight** arguments (`pkg/types/types.go`):

```go
PrivateBuyResultArgs = abi.Arguments{
    {Type: addressTy}, {Type: addressTy}, {Type: stringTy},
    {Type: uintTy}, {Type: uintTy}, {Type: uintTy},
    {Type: stringTy}, {Type: stringTy},          // ← lat, lon added later
}
```

and the extension packs eight values (`processWeatherBuy` → `PrivateBuyResultArgs.Pack(holder, contractAddr, date, rainThresholdMmE2, payout, premium, lat, lon)`). `abi.Arguments.Unpack` returns one value per argument, so `len(vals) == 8` always, and the decoder **always** returns `expected 6 values, got 8`. The `PrivateBuyResult` struct is likewise missing `Lat`/`Lon`.

Effect is confined to the types server's rendering of `WEATHER/BUY` results — it does not affect on-chain settlement. Low severity, trivially fixable, and a clean "while I was in here" item for the same PR.

`[Unverified]` by execution — Go is not installed in this environment (`which go` → not found). Experiment to settle: `cd fce-weather-insurance && go test ./pkg/types/...` after adding a round-trip test, or a three-line `main()` that packs eight values and calls the decoder.

**Patch:**

```diff
--- a/pkg/types/register.go
+++ b/pkg/types/register.go
 	vals, err := PrivateBuyResultArgs.Unpack(data)
 	if err != nil { return nil, err }
-	if len(vals) != 6 {
-		return nil, fmt.Errorf("expected 6 values, got %d", len(vals))
+	if len(vals) != 8 {
+		return nil, fmt.Errorf("expected 8 values, got %d", len(vals))
 	}
 	return PrivateBuyResult{
 		Holder:            vals[0].(common.Address),
 		ContractAddr:      vals[1].(common.Address),
 		Date:              vals[2].(string),
 		RainThresholdMmE2: vals[3].(*big.Int),
 		Payout:            vals[4].(*big.Int),
 		Premium:           vals[5].(*big.Int),
+		Lat:               vals[6].(string),
+		Lon:               vals[7].(string),
 	}, nil
```

plus `Lat`, `Lon` fields on `PrivateBuyResult`.

---

### 3.7 Defect (f) — `setExtensionId()` is O(n) *(new, watch item — not a blocker)*

I want to be precise here rather than inflate it.

`[Measured]` Live Coston2 reads, 2026-08-06, RPC `https://coston2-api.flare.network/ext/C/rpc`, `FlareTeeManager` = `0x1a9C4A0f9D76c0b1D91d22E24E573a9b377618aE`:

```
$ cast call $TEM "nextPublicExtensionId()(uint256)" --rpc-url $RPC
65966
```

`FIRST_PUBLIC_EXTENSION_ID` = `0x10000` = 65536, so **430 public extensions are already registered**. I spot-checked that the range is densely populated:

```
65536 -> 0x1663dAc32F95A04D71cEf5c3f832e315B9095C56
65600 -> 0x0b9cD8966206Adb2566E08B4A11fa43437980DCF
65900 -> 0xb51D5cF88153e1CC3E5303195882d81549aFcAaf
65965 -> 0xd59927d14484D9D060BDAb599B4c2c2904264f60
65966 -> 0x0000000000000000000000000000000000000000   (next free slot)
```

Because the registry assigns IDs ascending and `setExtensionId()` scans ascending, **our extension's ID is always the last one the loop reaches** — worst case every time. A Trimmy extension registered today performs ~431 external staticcalls in one transaction.

`[Measured]` A single `getTeeExtensionInstructionsSender(uint256)` call estimates at **28,994 gas** from an EOA (`cast estimate`, includes the 21,000 base tx cost).

`[Measured]` Coston2 block gas limit at block 33,687,687: **28,000,000**.

`[Inference]` In-loop cost per iteration is much lower than the EOA estimate — the target address is warm after the first call, so per-iteration is roughly a cold `SLOAD` (2,100) plus diamond dispatch and ABI overhead, call it 3,000–5,000 gas. That puts `setExtensionId()` at roughly **1.3M–2.2M gas** today, against a 28M limit.

**Verdict: not currently a problem.** It fits comfortably, it is a one-time call, and I am not recommending we change a function the scaffold marks `DO NOT MODIFY`. It becomes a real problem only somewhere north of ~6,000 registered extensions. I flag it because (i) the count is visibly growing during a hackathon and (ii) if `setExtensionId()` ever reverts on gas, the failure will look like an unrelated deploy bug. If it does bite, the fix is to add an owner-settable override:

```solidity
function setExtensionIdManual(uint256 _id) external onlyOwner {
    require(_extensionId == 0, "Extension ID already set.");
    require(TEE_EXTENSION_REGISTRY.getTeeExtensionInstructionsSender(_id) == address(this), "not ours");
    _extensionId = _id;
}
```

`register-extension` already prints the minted ID, so the operator always has it.

---

### 3.8 Suggested PR shape

Two PRs, not one — they have different reviewers and different risk profiles.

**PR 1 — `fce-extension-scaffold`: deploy-reliability fixes.** Defects (b), (c), (d), plus the `check-versions.sh` floor from (a). All four are small, self-contained shell/Go changes, each independently justifiable, and (d) is a straight port of code that already exists in `fce-sign`. Title suggestion: *"post-build/pre-build/start-services: make the Coston2 deploy path re-run safe"*.

**PR 2 — `fce-extension-scaffold` + `fce-weather-insurance`: bump tee-node to v0.0.25.** Defect (a), argued from the v0.0.23 audit fixes (quote the loopback commit message). Keep it separate because it touches `go.sum` in four modules and needs a build/test run the reviewer will want isolated. Fold (e) in only if the maintainers prefer one weather-repo PR.

---

## 4. Full deployment lifecycle on Coston2

This section is the runbook. It reflects the **scaffold**, which differs from `fce-sign` in ways the shared documentation blurs.

### 4.1 Scaffold vs fce-sign — do not mix the instructions

`[Verified]` by reading both `use-chain.sh` scripts:

| | scaffold | fce-sign |
|---|---|---|
| `use-chain.sh` arity | **one** arg: `./scripts/use-chain.sh coston2` | three: `./scripts/use-chain.sh local coston2 go` |
| Ships `.env.<chain>`? | **No** — only `.env.example` | Yes: `.env.coston2`, `.env.local.coston2` |
| `pre-build.sh --force`? | **No guard at all** (defect d) | Yes |
| Language selection | `LANGUAGE=` in `.env` + `<lang>/language.env` | `LANGUAGE=` in `.env.<chain>` |
| Types server | Absent | Absent (present only in weather-insurance) |

The scaffold's `use-chain.sh` copies `.env.<chain>` → `.env` and refuses if the source is missing:

```bash
if [[ ! -f "$SRC" ]]; then
    log "no .env.$CHAIN in $PROJECT_DIR"
    log "available chains:"
    list_chains          # prints "(none — create .env.<chain> from .env.example)"
    exit 1
fi
```

**So step zero on the scaffold is `cp .env.example .env.coston2` — this is not documented and `--list` will report "none" on a fresh clone.** `[Verified]` — `ls -a` on the clone shows `.env.example` as the only `.env*` file.

### 4.2 Prerequisites

- Docker Desktop (compose v2), Foundry (`forge`, `cast`), Go 1.25.1+, `jq`, `curl`
- A Coston2 account funded from <https://faucet.flare.network/coston2>
- An HTTPS tunnel binary: `ngrok` or `cloudflared`
- Indexer DB credentials (see 4.5)

### 4.3 Step 0 — create and activate the chain env

```bash
cp .env.example .env.coston2
$EDITOR .env.coston2          # see the table below
./scripts/use-chain.sh coston2
```

`use-chain.sh` echoes a summary; confirm `DEPLOYMENT_PRIVATE_KEY = <set>`.

**Every environment variable that matters** (`[Verified]` from `.env.example`, `docker-compose*.yaml`, and each script's header):

| Variable | Where consumed | Coston2 value / note |
|---|---|---|
| `LANGUAGE` | `start-services.sh` → `EXTENSION_DOCKERFILE` | `go` (only bit-for-bit reproducible option) |
| `DEPLOYMENT_PRIVATE_KEY` | `pre-build.sh`, `post-build.sh` (tools) | funded hex, **no `0x`** |
| `INITIAL_OWNER` | compose → node container | address derived from the above |
| `CHAIN_URL` | all tools | `https://coston2-api.flare.network/ext/C/rpc` |
| `CHAIN_ID` | compose → node (signature binding) | `114` (set by `docker-compose.coston2.yaml`) |
| `ADDRESSES_FILE` | `pre/post-build`, `test` | `./config/coston2/deployed-addresses.json` |
| `LOCAL_MODE` | script chain selection | `false` |
| `SIMULATED_TEE` | `post-build.sh` → `register-tee` | `true` for a laptop TEE; `false` on a real Confidential VM |
| `MODE` | compose → node attestation backend | `1` with `SIMULATED_TEE=true`; `0` with `false` |
| `NORMAL_PROXY_URL` | `post-build.sh` (FTDC) | `https://tee-proxy-coston2-1.flare.rocks` |
| `EXT_PROXY_URL` | `post-build.sh`, `start-services.sh`, `test.sh` | your public tunnel HTTPS URL |
| `EXT_PROXY_HOST_URL` | `post-build.sh` `register-tee -h` | optional; defaults to `EXT_PROXY_URL` |
| `PROXY_PRIVATE_KEY` | compose → ext-proxy | dev key is fine on testnet |
| `GOVERNANCE_SIGNERS` | `set-governance` **and** node container | leave unset → deployer, threshold 1 |
| `GOVERNANCE_THRESHOLD` | same | leave unset → `1` |
| `TEE_VERSION` | `post-build.sh` `allow-tee-version` | defaults `v0.1.0`; ≤ 32 bytes |
| `SOURCE_DATE_EPOCH` | Dockerfile reproducibility | auto-derived from git by `start-services.sh` |
| `REGISTRY` | compose image prefix | leave unset → builds `local/tee-proxy` |
| `COMPOSE_NETWORK` | compose network name | `extension-scaffold-coston2` (set by the overlay) |
| `WAIT_TIMEOUT` | `post-build.sh` service waits | default `120` s |
| `REGISTER_TEE_COMMAND` | *only after applying patch (b)* | `rRap` |

**Critical consistency rule** `[Verified]` from `docker-compose.yaml` comments: `SIMULATED_TEE` and the container's `MODE` must agree. `SIMULATED_TEE=true` ⇔ `MODE=1`; `SIMULATED_TEE=false` ⇔ `MODE=0`. Mismatch surfaces as `code hashes do not match`.

### 4.4 Step 1 — reserve the public proxy URL **before** anything else

The proxy URL is written on-chain during `register-tee`, so it must be final before `post-build.sh`. Reserve it first.

```bash
ngrok http 6674        # free tier keeps the URL stable across restarts
# or:
cloudflared tunnel --url http://localhost:6674
```

Copy the HTTPS forwarding URL into `EXT_PROXY_URL` in `.env.coston2`, then **re-run `./scripts/use-chain.sh coston2`** so `.env` picks it up.

**Why 6674 specifically** `[Verified]` from `docker-compose.yaml` and `tee-proxy/internal/server/external.go`:

| Service | Container port | Host port | Role |
|---|---|---|---|
| ext-proxy **internal** | 6663 | 6673 | node → proxy (`POST /result`, `POST /queue/{id}`) |
| ext-proxy **external** | 6664 | **6674** | public API (`GET /info`, `GET /action/result/{id}`, `POST /instruction`, `POST /direct`) |
| redis | 6379 | 6382 | proxy queue store |

Only 6674 is tunnelled. Tunnelling 6673 would expose the node↔proxy control path — do not.

> Security: the tunnel makes your local proxy world-reachable. Testnet only; tear the tunnel down when finished. Note that `POST /direct` (§5.4) is **API-key protected but off by default**; if you enable it, set a real key.

### 4.5 Step 2 — proxy config with indexer DB credentials

```bash
cp config/proxy/extension_proxy.coston2.docker.toml.example \
   config/proxy/extension_proxy.coston2.docker.toml
```

The template `[Verified]` (`.example`, verbatim), with the `[db]` block filled from the hackathon credentials:

```toml
# Docker-specific Coston2 proxy config. Service names instead of localhost.
redis_port = "redis:6379"
private_key_variable = "PROXY_PRIVATE_KEY"
initial_signing_policy_offset = 2
signing_policy_fetch_interval = "20s"

chain_id = 114

[db]
host = "34.38.42.208"
port = 3306
database = "indexer"
username = "hackathon_user_57"
password = "q0El26Hs7Yq8qdN2lBdjGyc7"
log_queries = false

[addresses]
flare_systems_manager = "0xA90Db6D10F856799b10ef2A77EBCbF460aC71e52"
relay                 = "0xa10B672D1c62e5457b17af63d4302add6A99d7dE"
voter_registry        = "0x6a0AF07b7972177B176d3D422555cbc98DfDe914"

[ports]
internal = "6663"
external = "6664"

[info_timing]
cycle_internal = "10s"
cycle_queue_response_wait = "2s"

[voting]
proposal_expiration = "12s"
max_pending_request = 10000
```

`[Verified]` The three `[addresses]` values in the shipped `.example` match `config/coston2/deployed-addresses.json` exactly (`FlareSystemsManager`, `Relay`, `VoterRegistry`).

`initial_signing_policy_offset = 2` is deliberate — it starts the proxy two reward epochs back to stay in sync, and pairs with the `CheckFTDCProxyPolicyConsistency` pre-flight. Do not set it to 0. `[Verified]` `fce-sign/SCAFFOLD_SYNC_UPDATE.md` §6.

### 4.6 Step 3 — `pre-build.sh`

```bash
./scripts/pre-build.sh
```

Does four things `[Verified]`:

0. `generate-bindings.sh` — `forge build` + `abigen`. Must run first: `tools/` imports the generated bindings, so nothing in `tools/` compiles on a fresh clone until this runs.
1. `check-versions.sh` pre-flight, then `deploy-contract --preflight-only`
2. `deploy-contract` → `INSTRUCTION_SENDER`
3. `register-extension --instructionSender <addr>` → `EXTENSION_ID`
4. writes `config/extension.env`:
   ```
   EXTENSION_ID=0x…        (64 hex)
   INSTRUCTION_SENDER=0x…  (40 hex)
   ```
   plus `config/deploy.log` (stderr from the Go tools).

**⚠ Until patch (d) lands, do not run this twice.** See §3.5.

### 4.7 Step 4 — start the stack

```bash
./scripts/start-services.sh --chain coston2
```

`[Verified]` sequence: resolve `LANGUAGE` from `<lang>/language.env` → derive `TEE_NODE_REF` from the go.mod pin → derive `SOURCE_DATE_EPOCH` from `git log -1 --format=%ct` → build `local/tee-proxy` from `proxy/Dockerfile` if absent → `docker compose -f docker-compose.yaml -f docker-compose.coston2.yaml up -d --build` → wait for `${EXT_PROXY_URL}/info` (120 s) → warn if `EXTENSION_ID` is absent from the `/info` payload.

Note the wait targets `EXT_PROXY_URL`, i.e. it goes out through your tunnel and back. Have the tunnel running. To wait locally instead:

```bash
until curl -sf http://localhost:6674/info >/dev/null 2>&1; do sleep 2; done
lsof -i :6674     # confirm only ext-proxy is bound
```

### 4.8 Step 5 — verify the proxy before registering

```bash
curl -s "$EXT_PROXY_URL/info" | jq '.machineData'
```

Expect: `extensionId` equal to `config/extension.env`, `initialOwner` equal to your address, and `codeHash` = `0x194844cf417dde867073e5ab7199fa4d21fd82b5dbe2bdea8b3d7fc18d10fdc2` in simulated mode. `[Verified]` — that constant is the documented simulated code hash in `tee-node/docs/attestation.md`. On a real Confidential VM, `platform` starts `0x4743505f414d445f534556…` (`GCP_AMD_SEV`) and `codeHash` is the real image digest.

### 4.9 Step 6 — `post-build.sh`

```bash
./scripts/post-build.sh
```

Three on-chain steps `[Verified]`, after waiting for both `${EXT_PROXY_URL}/info` and `${NORMAL_PROXY_URL}/info`:

1. **`allow-tee-version`** — `TeeExtensionRegistry.addTeeVersion(extensionId, bytes32(version), codeHash, [platform])`. Whitelists the measured code hash.
2. **`set-governance`** — computes `governanceHash = types.GovernanceHash(signers, threshold)` and registers it via `ExtensionGovernance.SetNewTeeGovernance`. Idempotent (skips when the on-chain hash already matches). Must equal what the node container was given.
3. **`register-tee`** — `r` pre-register / refresh attestation → `a` FTDC availability check → `p` `toProduction`. **Add `-command rRap`** (patch b).

State is checkpointed to `config/register-tee.state` after each step; `--resume` reuses it, otherwise it is deleted at start.

### 4.10 Step 7 — `test.sh`

```bash
./scripts/test.sh
```

`[Verified]` Loads `config/extension.env`, pre-flights `${EXT_PROXY_URL}/info`, then runs `tools/cmd/run-test` with `-a`, `-c`, `-p`, `-instructionSender`. For Trimmy this is the file we replace with our own E2E assertions.

### 4.11 Generated / gitignored files

| Path | Produced by | Committed? |
|---|---|---|
| `.env` | `use-chain.sh` | no (`.env*` ignored) |
| `.env.coston2` | you, from `.env.example` | no |
| `config/extension.env` | `pre-build.sh` | no |
| `config/deploy.log` | `pre-build.sh` | no |
| `config/register-tee.state` | `register-tee` | no |
| `config/proxy/extension_proxy.coston2.docker.toml` | you, from `.example` | no (credentials) |
| `tools/pkg/contracts/*/autogen.go`, `.abi`, `.bin` | `generate-bindings.sh` | no |
| `go.work`, `go.work.sum` | `start-services.sh` when `USE_LOCAL_SIBLINGS=1` | no |
| `out/`, `cache/` | `forge` | no |

### 4.12 Failure modes → fixes

`[Verified]` from repo docs, the `registration.go` guards I read, and the compose comments.

| Symptom | Cause | Fix |
|---|---|---|
| `cannot create subdirectories … not a directory` at compose up | missing `extension_proxy.coston2.docker.toml`; Docker made a directory | `rmdir` the stray dir, `cp` the `.example`, fill `[db]` — §3.4 |
| `Verification.ChallengeExpired` | stale one-shot attestation challenge from the state file | `-command rRap`; or delete `config/register-tee.state` — §3.3 |
| `MachineManager.TooMany()` | `extension.env` ID ≠ the ID the TEE machine is registered under | usually caused by re-running `pre-build.sh` — §3.5. Restore the old `extension.env` and re-run only post-build + test |
| `InvalidGovernanceHash` | `GOVERNANCE_SIGNERS`/`THRESHOLD` differ between `.env` (set-governance) and the node container | leave both unset for deployer-only, or align and re-run post-build |
| `InvalidTeePublicKeyOrSignature` | `CHAIN_ID` mismatch between node, proxy `chain_id`, and chain | all three must be `114` |
| `code hashes do not match` | `SIMULATED_TEE` vs `MODE` disagree | `true`↔`1`, `false`↔`0` |
| `Verification.TeeNotFound` | `NORMAL_PROXY_URL` points at the wrong chain's FTDC proxy | `https://tee-proxy-coston2-1.flare.rocks` |
| ext-proxy `connect: connection refused` / DB sync error | indexer DB unreachable or wrong creds | `docker compose logs ext-proxy`; host `34.38.42.208:3306` (`35.241.249.150` is **not** reachable) |
| proxy 404 "no round" during availability check | proxy signing policy out of sync with reward epoch | `CheckFTDCProxyPolicyConsistency` should now catch it; keep `initial_signing_policy_offset = 2` |
| tunnel URL changed | ngrok restarted on free tier | update `EXT_PROXY_URL`, re-run `use-chain.sh`, restart stack, re-run post-build + test |
| `context deadline exceeded` on `POST /action` | handler exceeded the node's synchronous budget | return status ≥ 2 and complete async via sign-port `POST /result` — §5.5 |

### 4.13 Full reset

```bash
./scripts/stop-services.sh --chain coston2
docker compose -f docker-compose.yaml -f docker-compose.coston2.yaml down --rmi local
rm -f .env config/extension.env config/register-tee.state \
      config/proxy/extension_proxy.coston2.docker.toml
```

On-chain state (deployed contracts, registered extensions, registered TEEs) cannot be reset.

---

## 5. Trimmy private-trigger extension — design

### 5.1 What we are building and why it is not a toy

Trimmy arms a rule with one XRPL payment. Today the rule can only see on-chain facts (FTSO price, FAssets state) or public web data (FDC Web2Json). The gap: **the facts that actually govern a person's money decisions are behind their own credentials.**

The FCC extension closes that gap: a trigger predicate evaluated inside an attested enclave over a data source the user authenticates to, emitting a signed boolean the Trimmy rule contract can act on — **without the credential, the raw balance, or the threshold ever appearing on-chain.**

### 5.2 Candidate data sources, assessed honestly

The brief asks which are *real, obtainable, and demonstrable*. Ranked by what we can actually stand up before 2026-08-14.

| Source | Trigger it enables | Real? | Obtainable in 8 days? | Demoable? | Verdict |
|---|---|---|---|---|---|
| **Centralised-exchange balance / position** (Kraken, Coinbase, Binance read-only API key) | "If my CEX XRP balance drops below X, pull Y from Flare"; "if my margin ratio < 1.3, top up" | **Yes** — read-only keys are a first-class feature | **Yes** — free, self-serve, minutes to create; HMAC-signed REST | **Yes** — real key, real account, real numbers | ✅ **Primary** |
| **Broker position** (Alpaca paper + live) | "If my equity drops below X, stop the DCA" | Yes | **Yes** — paper accounts are instant and free; same API shape as live | Yes — paper account is honest and demoable | ✅ **Secondary** |
| **Open-banking balance** (Plaid, TrueLayer, GoCardless) | "If my current account < €500, pause the DCA" | Yes | **Sandbox yes; production no** — production access needs an FCA/regulated entity and weeks of onboarding | Sandbox only | ⚠️ **Sandbox demo, name the limitation** |
| **Invoice / payables API** (Stripe, QuickBooks, Xero) | "When invoice #123 is paid, convert 30% to XRP" | Yes | Stripe test mode: yes. Others: OAuth app review | Stripe test mode, yes | ⚠️ **Stretch** |
| **Payroll API** (Gusto, Deel) | "On payday, DCA 5%" | Yes | **No** — partner-gated, no self-serve sandbox | No | ❌ **Cut** |
| **Private portfolio aggregator** (custom/self-hosted) | arbitrary | Yes | Yes, but it's our own API — proves nothing about the hard part | Weak | ❌ **Cut — self-dealing** |

**Recommendation: ship one, do it properly.** A read-only CEX API key is the strongest choice on every axis:

- It is the **exact** pain the Trimmy thesis names. Our whole pitch is "XRPL has no stop orders, so self-custody holders keep coins on an exchange." A trigger that reads the exchange the user was forced onto, and acts on Flare, closes the narrative loop.
- Read-only keys **cannot move funds**, so the demo is safe to run live on stage with a real account.
- It is the most adversarially interesting: a read-only key is exactly the kind of secret that must never touch a chain, and that Web2Json structurally cannot carry (§1.2).

Add Alpaca paper as a second `OPCommand` only if time remains — it demonstrates the source-adapter abstraction generalises, at low cost.

### 5.3 Credential delivery — the crux

`fce-sign`'s warning is unambiguous `[Verified]` (`fce-sign/README.md`):

```
> **Warning**: This repo is for demonstration purposes only. Storing encrypted
> secrets on-chain is not advisable in production — on-chain data is public
> and encryption can be broken over time. A production extension should use
> off-chain channels for secret delivery.
```

Both reference apps put ciphertext on-chain anyway (`fce-sign` `updateKey`; `fce-weather-insurance` `buyPolicyPrivate` sends ECIES ciphertext as a `WEATHER/BUY` instruction message). **We must not copy that.** ECIES to a TEE key is fine cryptographically; putting the ciphertext in permanent public storage is what fails — it is a harvest-now-decrypt-later target with an unbounded window.

I found **two** genuine off-chain channels in the codebase. They solve different problems and Trimmy needs both.

#### Channel A — Confidential Space env override (for *operator-held*, shared secrets)

`[Verified]` This is what `fce-weather-insurance` actually uses for its API key, and it is production-legitimate:

`fce-weather-insurance/Dockerfile`:
```dockerfile
LABEL "tee.launch_policy.allow_env_override"="LOG_LEVEL,PROXY_URL,INITIAL_OWNER,EXTENSION_ID,CHAIN_URL,MODE,CONFIG_PORT,SIGN_PORT,EXTENSION_PORT,OPENWEATHERMAP_API_KEY"
```
`internal/config/config.go`:
```go
OpenWeatherMapAPIKey = os.Getenv("OPENWEATHERMAP_API_KEY")
```

The allow-list is **baked into the image**, so it is part of the image digest, and the image digest **is the attested code hash** `[Verified]` (`tee-node/pkg/attestation/attestation_token.go`):

```go
func (c *NeededClaims) CodeHash() (common.Hash, error) {
	ch, err := convert.Hex32StringToCommonHash(strings.TrimPrefix(c.SubMods.Container.ImageID, "sha256:"))
	...
}
```

So anyone can verify on-chain *which env vars the workload is permitted to receive*, even though the values themselves are supplied by the VM operator at boot and are **not** in the attested claims (`NeededClaims` carries only `hwmodel` and `submods.container.image_id` — nothing else). `[Verified]`

**Use for:** our own infrastructure secrets — e.g. an outbound egress proxy token, a rate-limit key. **Not usable for per-user credentials**, because it is one value per deployment set by the operator.

#### Channel B — `POST /direct` on the proxy's external port (for *per-user* secrets) ← **this is the answer**

`[Verified]` `tee-proxy/internal/server/external.go`. The external server (host port 6674) registers an optional endpoint:

```go
func (e *External) registerRoutes(enableDirect bool) {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /instruction", ...)
	mux.HandleFunc("GET /info", ...)
	mux.HandleFunc(fmt.Sprintf("GET /action/result/{%s}", actionID), ...)
	if enableDirect {
		mux.HandleFunc("POST /direct", prepareHandler(e.directH, sizeLimit, false))
	}
	...
}
```

with API-key auth:

```go
func (e *External) verifyAPIKey(r *http.Request) error {
	key := r.Header.Get("X-API-Key")
	if subtle.ConstantTimeCompare([]byte(key), []byte(e.direct.APIKey)) != 1 { ... return errUnauthorized }
	return nil
}

func (e *External) directH(w http.ResponseWriter, r *http.Request) error {
	if !e.direct.APIKeyOptional {
		if err := e.verifyAPIKey(r); err != nil { return err }
	}
	i := new(types.DirectInstruction)
	dec := json.NewDecoder(r.Body); dec.DisallowUnknownFields()
	if err := dec.Decode(&i); err != nil { return ErrInvalidBody }
	if err := validateDirect(i); err != nil { return err }        // rejects system OPTypes
	a, err := queue.DirectInstructionToAction(i)
	...
	err = e.actionQueues.Enqueue(r.Context(), a, processorutils.Direct)
	...
	return json.NewEncoder(w).Encode(a)                            // returns the Action (incl. its ID)
}
```

The payload type is minimal `[Verified]` (`tee-node/pkg/types/direct.go`):

```go
type DirectInstruction struct {
	OPType    common.Hash   `json:"opType"`
	OPCommand common.Hash   `json:"opCommand"`
	Message   hexutil.Bytes `json:"message"`
}
```

and it reaches our handler `[Verified]` (`tee-node/internal/processors/direct/default.go`):

```go
func (p DefaultProcessor) Process(_ context.Context, a *types.Action) types.ActionResult {
	di, err := processorutils.Parse[types.DirectInstruction](a.Data.Message)
	if err != nil { return processorutils.Invalid(a, err) }
	if !op.IsValidPair(di.OPType, di.OPCommand) {
		return processorutils.Invalid(a, errors.New("invalid OPType, OPCommand pair"))
	}
	result, err := extension.PostActionToExtension(
		fmt.Sprintf("http://localhost:%d/action", p.extensionPort), a)
	...
}
```

**This is a complete off-chain request/response path into the enclave.** No transaction, no calldata, no fee, no permanent public record. The result is still signed by the TEE key and still verifiable on-chain by the same `TEE_ACTION_RESULT` recovery (§2.6).

Enable it by adding to `extension_proxy.coston2.docker.toml` `[Verified]` (toml tags from `tee-proxy/pkg/config/config.go`):

```toml
[direct]
enable           = true
api_key_variable = "DIRECT_API_KEY"   # value from env, never in the file
api_key_optional = false
max_body_size    = 65536
```

and pass `DIRECT_API_KEY` to the `ext-proxy` container.

**Three constraints I verified that a naive implementation would miss:**

1. **Direct actions carry a different message shape.** `[Verified]` — I traced the construction directly, `tee-proxy/internal/queue/action.go`:

   ```go
   func DirectInstructionToAction(i *types.DirectInstruction) (*types.Action, error) {
       id, err := random.Hash()          // NOTE: random ID, not an on-chain instruction ID
       dim, err := json.Marshal(i)       // ← the message is a JSON DirectInstruction …
       ad := types.ActionData{
           ID:            id,
           Type:          types.Direct,  // ← … and the Type field says so
           SubmissionTag: types.Submit,  // ← which is why the 30-min Submit TTL applies
           Message:       dim,
       }
       ...
   }
   ```

   For an on-chain instruction, `action.Data.Message` is an ABI-encoded `instruction.DataFixed`. For a direct action it is **JSON**. The scaffold's `processAction` unconditionally does `processorutils.Parse[instruction.DataFixed](action.Data.Message)` and **will fail on every direct action**. Trimmy's `processAction` must branch on `action.Data.Type` (`types.Instruction` vs `types.Direct`) *first*, then parse the appropriate shape. This single line is the difference between `/direct` working and returning `decoding fixed data: …` forever.

   Note also that a direct action's ID is `random.Hash()` — there is no on-chain instruction to correlate it with, which is precisely why it leaves no public trace, and why the client must capture the returned `Action.ID` from the `POST /direct` response body to poll for its result.
2. **OPType must not start with `F_`** — `validateDirect` rejects system types and `op.IsValid` returns `!t.isF()` for everything else (§2.4). `TRIMMY` is safe.
3. **Direct results expire fast.** `[Verified]` `tee-proxy/pkg/config/config.go`: `SubmitResultTTL` — *"Retention for Submit results. Defaults to 30 minutes."* Direct actions use `SubmissionTag: types.Submit`. The client must poll `GET /action/result/{id}` promptly; results are not durable.

#### The credential protocol Trimmy will use

```
1. Client: GET  ${EXT_PROXY_URL}/info                    → TEE public key + codeHash + extensionId
2. Client: verify codeHash on-chain — TeeExtensionRegistry says this hash is whitelisted
           for extension EXTENSION_ID. Verify the reproducible build matches our published
           source (REPRODUCIBILITY.md). ONLY THEN proceed.
3. Client: ct = ECIES(teePubKey, abi.encode(CredentialBundle))
4. Client: POST ${EXT_PROXY_URL}/direct
           X-API-Key: <direct key>
           {"opType": keccakless_bytes32("TRIMMY"),
            "opCommand": bytes32("CRED_PUT"),
            "message": "0x<ct>"}
5. Enclave: POST /decrypt on SIGN_PORT (loopback, v0.0.25) → plaintext
            store in memory keyed by credentialId = keccak256(owner, ruleId)
            NEVER persist to disk, NEVER log, NEVER return in ActionResult.Data
6. Enclave: returns ActionResult{ Data: abi.encode(credentialId, expiresAt), Status: 1 }
7. Client: poll GET ${EXT_PROXY_URL}/action/result/{actionId} (within 30 min)
8. Client: one on-chain tx binds credentialId → ruleId in TrimmyRuleRegistry.
           Only the 32-byte commitment goes on-chain. Never the credential.
```

Step 2 is the part that makes this trustworthy rather than "trust us": the user is not trusting Trimmy the company, they are trusting a code hash that is whitelisted on-chain and reproducible from published source.

**Honest limitations to state in the submission** `[Inference]`:

- **Enclave memory is volatile.** A VM restart loses every credential and every user must re-provision. `tee-node` has a wallet backup/restore subsystem, but it is for protocol-managed wallets, not arbitrary extension state. Options: (i) accept it and make re-provisioning one click; (ii) re-encrypt to the TEE key and persist to disk inside the VM. **(i) is correct for the hackathon** — it is honest, simple, and avoids inventing a persistence scheme we cannot audit in 8 days.
- **The `X-API-Key` on `/direct` is a shared deployment secret, not per-user auth.** It gates who may enqueue direct actions at all. Per-user authorisation must be inside the payload — sign the `CredentialBundle` with the user's Flare key and have the enclave recover it. Do not rely on the proxy key for authorisation.
- **We are the VM operator.** In a real deployment the operator and the app author should be different parties. We should say so plainly rather than overclaim the trust model.

### 5.4 OPType / OPCommand set

One OPType, five commands. All ≤ 31 bytes; none start with `F_`.

```solidity
bytes32 constant OP_TYPE_TRIMMY = bytes32("TRIMMY");

bytes32 constant OP_CMD_CRED_PUT    = bytes32("CRED_PUT");    // off-chain only (direct)
bytes32 constant OP_CMD_CRED_REVOKE = bytes32("CRED_REVOKE"); // off-chain or on-chain
bytes32 constant OP_CMD_ARM         = bytes32("ARM");         // on-chain: bind rule → credential
bytes32 constant OP_CMD_EVAL        = bytes32("EVAL");        // on-chain: evaluate, sign verdict
bytes32 constant OP_CMD_PROBE       = bytes32("PROBE");       // off-chain: dry-run, no signature
```

| Command | Channel | Purpose | Result data |
|---|---|---|---|
| `CRED_PUT` | **direct only** — reject if `action.Data.Type != Direct` | Decrypt + hold a credential | `abi.encode(bytes32 credentialId, uint64 expiresAt)` |
| `CRED_REVOKE` | either | Zeroise a held credential | `abi.encode(bytes32 credentialId, bool existed)` |
| `ARM` | on-chain | Bind `ruleId` → `(credentialId, predicate)`; return a terms commitment | `abi.encode(bytes32 ruleId, bytes32 termsCommitment, uint64 armedAt)` |
| `EVAL` | on-chain | Fetch, evaluate predicate, sign verdict | `abi.encode(TriggerVerdict)` (below) |
| `PROBE` | **direct only** | Same as `EVAL` but returns only a boolean + human-readable reason; used by the UI to show "would this fire right now?" without an on-chain tx | `abi.encode(bool, string)` |

Rationale for `EVAL` being on-chain: the *verdict* should be auditable and paid for, and the keeper's request should be a matter of public record. The *inputs* stay private. That is precisely the confidential-compute value proposition, and it is the opposite of `CRED_PUT`, where even the request must be private.

`PROBE` exists so the UI never needs to spend gas to answer "is my rule about to fire?", and — importantly — `PROBE` **must not return a TEE signature**, or it becomes a free oracle for the predicate. Return status 1 with unsigned data only.

### 5.5 Request / response structs

Solidity side, mirrored exactly in `pkg/types/types.go`.

```solidity
/// Encrypted off-chain via ECIES to the TEE public key. NEVER on-chain.
struct CredentialBundle {
    address owner;         // Flare address that owns this credential
    uint8   provider;      // 1=Kraken 2=Coinbase 3=Alpaca … (enum, not a string)
    string  apiKey;
    string  apiSecret;
    string  subaccount;    // "" if unused
    uint64  expiresAt;     // unix seconds; enclave refuses to use it after this
    uint64  nonce;         // replay protection for the ownerSig
    bytes   ownerSig;      // EIP-191 sig by `owner` over keccak256(abi.encode(all above))
}

/// ARM — on-chain. Contains NO credential material.
struct ArmParams {
    bytes32 ruleId;
    bytes32 credentialId;  // commitment returned by CRED_PUT
    uint8   metric;        // 1=free balance 2=total equity 3=margin ratio 4=position size
    string  asset;         // "XRP", "USD", …
    uint8   comparator;    // 0 = <  , 1 = >
    uint256 thresholdE8;   // fixed-point, 8 decimals
    uint64  cooldownSec;   // min seconds between fires
    uint64  expiresAt;
}

/// EVAL — on-chain request.
struct EvalRequest {
    bytes32 ruleId;
    address contractAddr;  // the TrimmyRule contract that will consume the verdict
    uint64  requestedAt;
}

/// EVAL — the signed result. This is what the contract acts on.
struct TriggerVerdict {
    address contractAddr;  // binds the verdict to one consumer contract
    bytes32 ruleId;
    bool    triggered;
    uint64  observedAt;    // enclave clock, unix seconds
    uint64  nonce;         // strictly increasing per ruleId — replay protection
    bytes32 termsCommitment; // keccak of the armed terms; proves which rule was evaluated
}
```

**Design decisions worth defending:**

- `TriggerVerdict` carries **`triggered`, not the balance.** The whole point is that the observed value never leaves the enclave. Returning the balance would leak exactly what we claim to protect. (`fce-weather-insurance` returns `precipitationMmE2` because rainfall is public; a bank balance is not — do not copy that shape.)
- `contractAddr` is inside the signed payload, so a verdict cannot be replayed against a different consumer contract. `fce-weather-insurance` does the same and it is the right pattern.
- `nonce` strictly increasing per `ruleId`, enforced both in the enclave and in the contract. Without it, a `triggered=true` verdict is replayable forever — the single most likely exploitable bug in this design.
- `termsCommitment` lets the contract prove the verdict corresponds to the terms the user armed, without those terms being on-chain.
- `provider` is a `uint8` enum, not a string — it keeps the ABI tight and stops the on-chain surface from carrying a provider name that is itself a small privacy leak.

### 5.5b The asynchronous `EVAL` execution model (forced by §2.6b)

Because `ProxyTimeout` is a 2-second `const`, `EVAL` cannot fetch-and-return in one call. The handler splits in two.

**Phase 1 — synchronous ack (must finish in ≪ 2 s, does no I/O):**

```go
func (e *Extension) processEval(action teetypes.Action, df *instruction.DataFixed) teetypes.ActionResult {
    var req types.EvalRequest
    if err := decodeABI(df.OriginalMessage, &req); err != nil {
        return buildResult(action, df, nil, 0, fmt.Errorf("decoding eval request: %w", err))
    }
    // Validate against in-memory state ONLY — no network, no disk.
    rule, ok := e.rules[req.RuleID]
    if !ok      { return buildResult(action, df, nil, 0, errors.New("rule not armed")) }
    if !e.hasCredential(rule.CredentialID) {
        return buildResult(action, df, nil, 0, errors.New("credential not provisioned"))
    }
    // Hand off and return immediately. Status 2 = pending, NOT an error.
    go e.completeEval(action, df, req, rule)
    return buildResult(action, df, nil, 2, nil)
}
```

**Phase 2 — background completion (unbounded, signs and posts its own result):**

```go
func (e *Extension) completeEval(action teetypes.Action, df *instruction.DataFixed,
                                 req types.EvalRequest, rule Rule) {
    ctx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
    defer cancel()

    observed, err := e.adapter(rule.Provider).Fetch(ctx, e.credential(rule.CredentialID), rule.Metric, rule.Asset)
    // Build the verdict. NOTE: `observed` never leaves this function.
    verdict := types.TriggerVerdict{
        ContractAddr:    req.ContractAddr,
        RuleID:          req.RuleID,
        Triggered:       err == nil && rule.Predicate(observed),
        ObservedAt:      uint64(time.Now().Unix()),
        Nonce:           e.nextNonce(req.RuleID),
        TermsCommitment: rule.TermsCommitment,
    }
    data, _ := types.TriggerVerdictArgs.Pack(verdict.Fields()...)

    final := teetypes.ActionResult{
        ID: action.Data.ID, SubmissionTag: action.Data.SubmissionTag,
        Version: config.Version, OPType: df.OPType, OPCommand: df.OPCommand,
        Data: data, Status: 1, Log: "ok",
    }
    // Sign via the loopback sign port, then post to the proxy ourselves.
    sig, err := e.signViaSignPort(final)          // POST http://127.0.0.1:${SIGN_PORT}/...
    if err != nil { logger.Errorf("eval: signing: %v", err); return }
    _ = postActionResponse(e.proxyURL+"/result", &teetypes.ActionResponse{Result: final, Signature: sig})
}
```

Five things this must get right, each learned from the verified code above:

1. **`ID` and `SubmissionTag` must be copied from the original action**, or `ActionResult.Hash()` changes and the contract's reconstruction fails (§2.6).
2. **Status 2 on the ack is "pending", not failure.** The keeper's client must treat `status >= 2` as *not final* and keep polling — and must not confuse it with the streamed-partial statuses `3, 4, 5…` upstream uses.
3. **The background context needs its own timeout.** Nothing upstream will cancel this goroutine for you; `ActionProcessTimeout` (10 s) bounds only the *synchronous* path.
4. **A failed fetch must still post a result**, with `status = 0`, or the keeper polls until the 30-minute TTL expires with no signal. The sketch above returns early on signing error but should post a `status = 0` result on fetch error.
5. **`observed` must never enter `Data`, `Log`, or any log line.** It is the exact value we promise never leaves the enclave. Only `Triggered` (a bool) is published.

`[Unverified]` The exact request shape of the sign-port endpoint the extension calls to sign an arbitrary `ActionResult`. I confirmed the sign server exists, binds loopback, and exposes `POST /decrypt` and `POST /decrypt/{walletID}/{keyID}`, but I did not enumerate its signing routes. *Experiment to settle:* read `tee-node/internal/extension/server/server.go` `registerRoutes()` in full and mirror the request struct — a 10-minute task, and it is a hard prerequisite for step 4b in the build plan.

### 5.6 Contract consumption

```solidity
bytes32 private constant TEE_ACTION_RESULT_PREFIX = bytes32("TEE_ACTION_RESULT");

mapping(bytes32 => uint64) public lastNonce;      // ruleId → last accepted nonce
mapping(bytes32 => uint64) public lastFiredAt;    // ruleId → cooldown anchor
address public teeAddress;

function fire(
    bytes calldata _resultData,     // abi.encode(TriggerVerdict)
    bytes32        _actionId,
    string calldata _submissionTag,
    uint8          _status,
    bytes calldata _signature
) external {
    require(teeAddress != address(0), "TEE address not set");
    require(_status == 1, "TEE result not successful");

    // 1. Recover exactly as tee-node signs (see §2.6)
    bytes32 resultHash = keccak256(abi.encodePacked(
        keccak256(_resultData), _actionId, keccak256(bytes(_submissionTag)), _status));
    bytes32 payloadHash = keccak256(abi.encode(
        TEE_ACTION_RESULT_PREFIX, block.chainid, resultHash));
    require(_recover(_ethSigned(payloadHash), _signature) == teeAddress, "bad TEE signature");

    // 2. Decode and bind
    TriggerVerdict memory v = abi.decode(_resultData, (TriggerVerdict));
    require(v.contractAddr == address(this), "wrong consumer");
    require(v.triggered, "not triggered");

    // 3. Replay + freshness + cooldown
    require(v.nonce > lastNonce[v.ruleId], "stale nonce");
    lastNonce[v.ruleId] = v.nonce;
    require(block.timestamp - v.observedAt <= MAX_VERDICT_AGE, "verdict too old");
    Rule storage r = rules[v.ruleId];
    require(v.termsCommitment == r.termsCommitment, "terms mismatch");
    require(block.timestamp >= lastFiredAt[v.ruleId] + r.cooldownSec, "cooldown");
    lastFiredAt[v.ruleId] = uint64(block.timestamp);

    // 4. Execute the armed action (the Smart Accounts user-op batch)
    _executeRule(v.ruleId);
}
```

`teeAddress` is set by `setTeeAddress(address)` under `onlyOwner`, read from `${EXT_PROXY_URL}/info`. `[Verified]` — same pattern as `fce-weather-insurance`.

`MAX_VERDICT_AGE` matters because `EVAL` is asynchronous: without it, a keeper could sit on a favourable verdict and submit it later.

### 5.7 How this composes with the rest of Trimmy

The XRPL arming payment (memo opcode `0xFE`) authorises a Trimmy executor contract for a bounded, rule-scoped set of calls. `fire()` above is the gate that releases one such execution. So the full chain is:

```
XRPL payment (0xFE memo) ──► Smart Account executeUserOp ──► TrimmyRuleRegistry.arm(ruleId, terms)
                                                                       │
user provisions credential off-chain ──► POST /direct CRED_PUT ────────┘
                                                                       │
keeper ──► InstructionSender.sendEval(ruleId) ──► TEE EVAL ──► signed TriggerVerdict
                                                                       │
anyone ──► TrimmyRule.fire(verdict, sig) ──► verify ──► executeUserOp(Call[] calls)
```

The user holds zero FLR throughout, and the only thing that ever touches a public ledger is a 32-byte commitment and a boolean.

### 5.8 Build plan against the deadline (2026-08-14 19:59)

`[Inference]` — sequencing, based on what the lifecycle in §4 actually requires.

| # | Task | Blocking? |
|---|---|---|
| 1 | Fork scaffold; apply patches (a)(b)(c)(d) **immediately** | Yes — (d) will otherwise burn an extension ID |
| 2 | `cp .env.example .env.coston2`; tunnel; proxy toml; walk §4 end-to-end **with the unmodified Hello World** | Yes — prove the pipeline before adding logic |
| 3 | Rename to `TRIMMY`; add `EVAL` returning a hardcoded verdict; get `fire()` verifying a real TEE signature on Coston2 | Yes — signature recovery is the highest-risk unknown |
| 4 | Enable `[direct]`; implement `CRED_PUT` + `/decrypt`; hold credential in memory | Yes |
| 4b | **Async result plumbing**: return `status>=2` fast, complete on a goroutine, sign via sign port, `POST ${PROXY_URL}/result` | **Yes — forced by the 2 s `ProxyTimeout`, §2.6b** |
| 5 | Kraken read-only adapter; real `EVAL` (on top of 4b, never synchronous) | Yes |
| 6 | Nonce/cooldown/age hardening; port the types server from weather-insurance | No |
| 7 | Alpaca adapter; `PROBE` for the UI | No |
| 8 | Open the two upstream PRs (§3.8) | No — but it is cheap and the hackathon rewards it |

Step 3 before step 4 is deliberate: signature recovery against `TEE_ACTION_RESULT` is where teams lose a day, and it is testable with a stub verdict.

---

## 6. Open questions

1. **Is v0.0.22 actually a hard minimum?** Not enforced anywhere in the scaffold (`check-versions.sh` does consistency checks only). *Experiment:* ask in the hackathon Telegram, or attempt `register-tee` on Coston2 with the v0.0.21 pin and see whether FTDC rejects the code hash. Does not block the bump — the v0.0.23 audit fixes justify it independently.
2. **Does the Web2Json `headers` field actually land in on-chain calldata?** *Experiment:* submit a Web2Json attestation request on Coston2 with a sentinel header value, then `cast tx <hash>` and grep the calldata. Not load-bearing — §1.2 point 1 is a schema-level impossibility and is fully verified.
3. **Is defect (e) reproducible at runtime?** Go is not installed here. *Experiment:* `cd fce-weather-insurance && go test ./pkg/types/...` with a round-trip test that packs 8 values and calls `privateBuyResultDecoder.Decode`.
4. ~~**What is the enclave's synchronous budget for `POST /action`?**~~ **RESOLVED — see §2.6b.** `[Verified]` in source: `settings.ProxyTimeout = 2 * time.Second`, a `const`, applied as the `http.Client.Timeout` in `PostActionToExtension`. Also `ActionProcessTimeout = 10s`, `ActionDrainTimeout = 5s`. No experiment needed. **`EVAL` must be async.** The only residual unknown is the observed latency distribution of the exchange call itself, which does not change the design.
5. **Can the extension reach the public internet from a real Confidential Space VM?** Weather-insurance calls OpenWeatherMap, so egress works in principle, but egress policy/NAT on our VM is unverified. *Experiment:* deploy and curl `api.kraken.com` from inside the workload.
6. **Does `POST /direct` survive the tunnel with a body of a few KB?** *Experiment:* enable `[direct]`, POST a 4 KB ECIES ciphertext through ngrok, confirm the action is enqueued and the result retrievable inside 30 min.
7. **Credential persistence across VM restart.** Recommending "accept volatility, re-provision" for the hackathon. *Experiment (post-hackathon):* evaluate sealing to disk with a TEE-derived key.

---

## 7. Appendix — verified constants

| Constant | Value | Source |
|---|---|---|
| Coston2 RPC | `https://coston2-api.flare.network/ext/C/rpc` | live read, `eth_chainId` → `0x72` = 114 |
| Coston2 `FlareTeeManager` | `0x1a9C4A0f9D76c0b1D91d22E24E573a9b377618aE` | `config/coston2/deployed-addresses.json`; `eth_getCode` non-empty |
| Coston2 `Fdc2Hub` | `0x04dd3Ba33aC798d400bEc42A26F82f9812A421dc` | same |
| Coston2 `FlareSystemsManager` | `0xA90Db6D10F856799b10ef2A77EBCbF460aC71e52` | same |
| Coston2 `Relay` | `0xa10B672D1c62e5457b17af63d4302add6A99d7dE` | same |
| Coston2 `VoterRegistry` | `0x6a0AF07b7972177B176d3D422555cbc98DfDe914` | same |
| Coston2 FTDC proxy | `https://tee-proxy-coston2-1.flare.rocks` | `.env.example` |
| `FIRST_PUBLIC_EXTENSION_ID` | `0x10000` = 65536 | `InstructionSender.sol` |
| `nextPublicExtensionId()` | 65966 (430 registered) | live read 2026-08-06 |
| Coston2 block gas limit | 28,000,000 | `cast block latest` |
| Simulated TEE code hash | `0x194844cf417dde867073e5ab7199fa4d21fd82b5dbe2bdea8b3d7fc18d10fdc2` | `tee-node/docs/attestation.md` |
| GCP AMD SEV platform prefix | `0x4743505f414d445f534556…` (`GCP_AMD_SEV`) | scaffold deploy docs |
| TEE result domain prefix | `bytes32("TEE_ACTION_RESULT")` | `fce-weather-insurance/contracts/InstructionSender.sol` |
| Reserved OPType prefix | `F_` | `go-flare-common/pkg/tee/op/op.go` |
| Direct result TTL | 30 minutes | `tee-proxy/pkg/config/config.go` |
| `tee-node` latest | `v0.0.25` (2026-08-05) | `proxy.golang.org/…/@latest` |
| `tee-proxy` latest | `v0.0.21` | `proxy.golang.org/…/@v/list` |
| Container ports (scaffold compose) | config 5501, sign 7701, extension 7702 | `docker-compose.yaml` env |
| Container ports (tee-node defaults) | config 5500, sign **8888**, extension **8889** | `tee-node/internal/settings/settings.go:113-115` |
| Host ports | proxy-internal 6673, proxy-external **6674**, redis 6382 | `docker-compose.yaml` |
| Sign-server bind host | `127.0.0.1` (`const SignHost`, not configurable) | `tee-node/internal/settings/settings.go:40` |
| **`ProxyTimeout` (handler budget)** | **2 s — `const`, not configurable** | `tee-node/internal/settings/settings.go:46` |
| `ActionProcessTimeout` | 10 s | same, line 54 |
| `ActionDrainTimeout` | 5 s | same, line 66 |
| `/direct` default body limit | 10 MiB (`instructionSizeLimit`) | `tee-proxy/internal/server/external.go:41` |
| TEE result signature field | `ActionResponse.signature` (**not** `proxySignature`) | `tee-node/pkg/types/actions.go:40-44` |
| Proxy result domain prefix | `bytes32("PROXY_ACTION_RESULT")` | `go-flare-common/pkg/signing/prefixes.go` |
| Encoding version | `1.0.0` | `tee-node/internal/settings/settings.go` |
| Direct action ID | `random.Hash()` — no on-chain correlation | `tee-proxy/internal/queue/action.go:24` |
