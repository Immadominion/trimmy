// Package extension implements the Trimmy confidential-trigger extension.
//
// # What it keeps secret, and why that is the valuable thing
//
// An ordinary Trimmy rule stores its trigger price in `Rule.triggerValue`, on chain, readable by
// anyone. For a stop that is a problem, and not a subtle one: publishing "sell 50,000 FXRP if XRP
// drops below X" tells every observer the exact price at which a large, price-insensitive sell
// arrives. Trimmy's own adversarial review already established the related finding (A2) — the
// execution floor is a publicly computable target and an observer takes the whole slippage band
// with certainty. A published threshold is the same failure one step earlier.
//
// Flare's Data Connector cannot fix this. `Web2Json`'s source identifier is literally
// `PublicWeb2`: the request and its headers go on chain and ~100 providers each fetch it to reach
// consensus. That is what makes FDC trustworthy and exactly what makes it unable to hold a secret.
//
// So the threshold lives here, in enclave memory. The chain holds only
// `keccak256(threshold ‖ salt ‖ direction)`.
//
// # What this file deliberately does not do
//
//   - It does not fetch its own price. The caller supplies the observed price, because it must be
//     the SAME number the contract re-derives from FTSO when it executes. An enclave with its own
//     price source could disagree with the chain and the disagreement would be invisible.
//   - It never returns distance-to-trigger, or any value derived from the threshold beyond a single
//     boolean. Returning "how close" would let an observer binary-search the secret across repeated
//     evaluations, which defeats the entire design.
//   - It does not persist. Enclave memory is volatile and a restart loses every secret. That is
//     stated plainly rather than papered over: re-provisioning is one instruction, and a design
//     that survived restart would mean the secrets were written somewhere we could read.
package extension

import (
	"bytes"
	"encoding/json"
	"fmt"
	"math/big"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"extension-scaffold/internal/config"
	"extension-scaffold/pkg/types"

	"net"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/flare-foundation/go-flare-common/pkg/tee/instruction"
	teetypes "github.com/flare-foundation/tee-node/pkg/types"
	teeutils "github.com/flare-foundation/tee-node/pkg/utils"

	"github.com/flare-foundation/tee-node/pkg/processorutils"
)

// secret is one rule's confidential trigger. It exists only in enclave memory.
type secret struct {
	threshold  *big.Int
	commitment common.Hash
	direction  types.Direction
	account    string
}

type Extension struct {
	mu     sync.RWMutex
	Server *http.Server

	// Keyed by rule id. Never logged, never exposed by /state, never returned by any handler.
	secrets map[uint64]*secret

	evaluations    int
	firedVerdicts  int
	provisionsSeen int
	lastEvaluated  int64

	// decrypt is the enclave's ECIES decryption. It is a field, not a direct call, so the suite
	// can exercise the handlers without a running TEE — and, more importantly, so that a test can
	// assert PLAINTEXT IS REFUSED. Defaults to the real enclave port; never nil in production.
	decrypt func([]byte) ([]byte, error)
}

// --- DO NOT MODIFY: New(), actionHandler() are boilerplate.
func New(extensionPort, signPort int) *Extension {
	e := &Extension{secrets: make(map[uint64]*secret), decrypt: decryptInEnclave}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /state", e.stateHandler)
	mux.HandleFunc("POST /action", e.actionHandler)

	e.Server = &http.Server{Addr: fmt.Sprintf(":%d", extensionPort), Handler: mux}
	return e
}

// stateHandler reports counts and never contents. An operator needs to know the extension is alive
// and how many secrets it holds; nobody, including us, needs an endpoint that lists them.
func (e *Extension) stateHandler(w http.ResponseWriter, r *http.Request) {
	e.mu.RLock()
	state := types.State{
		Version:         config.Version,
		SecretsHeld:     len(e.secrets),
		Evaluations:     e.evaluations,
		FiredVerdicts:   e.firedVerdicts,
		ProvisionsSeen:  e.provisionsSeen,
		LastEvaluatedAt: e.lastEvaluated,
	}
	e.mu.RUnlock()

	if err := json.NewEncoder(w).Encode(map[string]any{
		"stateVersion": teeutils.ToHash(config.Version),
		"state":        state,
	}); err != nil {
		http.Error(w, fmt.Sprintf("sending response: %v", err), http.StatusInternalServerError)
	}
}

func (e *Extension) processAction(action teetypes.Action) (int, []byte) {
	dataFixed, err := processorutils.Parse[instruction.DataFixed](action.Data.Message)
	if err != nil {
		return http.StatusBadRequest, []byte(fmt.Sprintf("decoding fixed data: %v", err))
	}

	switch {
	case dataFixed.OPType == teeutils.ToHash(config.OPTypeTrimmy):
		return e.processTrimmy(action, dataFixed)

	default:
		return http.StatusNotImplemented, []byte(fmt.Sprintf(
			"unsupported op type: received %s, expected %s (%s)",
			dataFixed.OPType.Hex(), teeutils.ToHash(config.OPTypeTrimmy).Hex(), config.OPTypeTrimmy,
		))
	}
}

func (e *Extension) processTrimmy(action teetypes.Action, df *instruction.DataFixed) (int, []byte) {
	switch {
	case df.OPCommand == teeutils.ToHash(config.OPCommandProvision):
		ar := e.processProvision(action, df)
		b, _ := json.Marshal(ar)
		return http.StatusOK, b

	case df.OPCommand == teeutils.ToHash(config.OPCommandEvaluate):
		ar := e.processEvaluate(action, df)
		b, _ := json.Marshal(ar)
		return http.StatusOK, b

	case df.OPCommand == teeutils.ToHash(config.OPCommandForget):
		ar := e.processForget(action, df)
		b, _ := json.Marshal(ar)
		return http.StatusOK, b

	default:
		return http.StatusNotImplemented, []byte(fmt.Sprintf(
			"unsupported op command: received %s, expected one of [%s (%s), %s (%s), %s (%s)]",
			df.OPCommand.Hex(),
			teeutils.ToHash(config.OPCommandProvision).Hex(), config.OPCommandProvision,
			teeutils.ToHash(config.OPCommandEvaluate).Hex(), config.OPCommandEvaluate,
			teeutils.ToHash(config.OPCommandForget).Hex(), config.OPCommandForget,
		))
	}
}

// commitmentOf is the ONE definition of the commitment, used by provisioning and by the contract.
//
// The direction is bound into it deliberately. Without that, a threshold provisioned for
// PRICE_BELOW would satisfy a rule armed as PRICE_ABOVE at the same number, and the rule would fire
// on exactly the wrong side of the market.
func commitmentOf(threshold *big.Int, salt string, dir types.Direction) common.Hash {
	var buf bytes.Buffer
	buf.WriteString(threshold.String())
	buf.WriteByte(0x1f) // unit separator: keeps "1"+"23" from colliding with "12"+"3"
	buf.WriteString(salt)
	buf.WriteByte(0x1f)
	buf.WriteByte(byte(dir))
	return crypto.Keccak256Hash(buf.Bytes())
}

// decryptInEnclave asks the TEE node to ECIES-decrypt a payload with its own private key.
//
// This is what makes the threshold ACTUALLY secret rather than nominally so. The instruction that
// carries it travels on chain, so it must arrive as ciphertext; the only party that can read it is
// the enclave, because the decryption key exists nowhere else. An earlier version of this handler
// decoded plaintext JSON straight off the instruction — which would have published every user's
// stop price on a public ledger while the documentation claimed the opposite.
//
// The sign/decrypt API is bound to loopback inside the enclave and is unauthenticated, so it must
// never be reachable from outside it. That is the node's design, not ours.
func decryptInEnclave(ciphertext []byte) ([]byte, error) {
	body, err := json.Marshal(teetypes.DecryptRequest{EncryptedMessage: ciphertext})
	if err != nil {
		return nil, fmt.Errorf("encoding decrypt request: %w", err)
	}

	url := "http://" + net.JoinHostPort("127.0.0.1", strconv.Itoa(config.SignPort)) + "/decrypt"
	resp, err := http.Post(url, "application/json", bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("calling the enclave decrypt port: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		// Deliberately does not echo the node's message: it is derived from attacker-supplied
		// ciphertext, and this string reaches an on-chain result.
		return nil, fmt.Errorf("enclave refused to decrypt (status %d)", resp.StatusCode)
	}

	var out teetypes.DecryptResponse
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, fmt.Errorf("decoding decrypt response: %w", err)
	}
	if len(out.DecryptedMessage) == 0 {
		return nil, fmt.Errorf("enclave returned an empty plaintext")
	}
	return out.DecryptedMessage, nil
}

// processProvision stores a rule's secret threshold.
//
// The payload arrives ECIES-encrypted to the enclave's public key and is decrypted HERE, inside the
// enclave. The plaintext threshold exists only in this process's memory and is never written to
// disk, never logged, and never returned by any handler.
func (e *Extension) processProvision(action teetypes.Action, df *instruction.DataFixed) teetypes.ActionResult {
	if e.decrypt == nil {
		// Refusing beats guessing: a nil decryptor would otherwise be indistinguishable from
		// "this payload happened to be readable", which is the failure we are guarding against.
		return buildResult(action, df, nil, 0, fmt.Errorf("no decryptor configured"))
	}
	plaintext, err := e.decrypt(df.OriginalMessage)
	if err != nil {
		return buildResult(action, df, nil, 0, err)
	}

	var req types.ProvisionRequest
	dec := json.NewDecoder(bytes.NewReader(plaintext))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&req); err != nil {
		// Note the message: it says nothing about WHAT failed to parse. The plaintext is a user
		// secret and this error is written on chain.
		return buildResult(action, df, nil, 0, fmt.Errorf("provision payload is not valid JSON"))
	}

	// Every field is untrusted input.
	threshold, ok := new(big.Int).SetString(strings.TrimSpace(req.Threshold), 10)
	if !ok || threshold.Sign() <= 0 {
		return buildResult(action, df, nil, 0, fmt.Errorf("threshold must be a positive decimal integer"))
	}
	if len(req.Salt) < 16 {
		// A short salt makes the commitment brute-forceable: the plausible range of a stop price
		// is small and the hash is public, so the salt is what makes it hiding rather than merely
		// binding.
		return buildResult(action, df, nil, 0, fmt.Errorf("salt must be at least 16 characters"))
	}
	if req.Direction != types.DirectionBelow && req.Direction != types.DirectionAbove {
		return buildResult(action, df, nil, 0, fmt.Errorf("direction must be 0 (below) or 1 (above)"))
	}
	if req.Account == "" {
		return buildResult(action, df, nil, 0, fmt.Errorf("account must not be empty"))
	}

	c := commitmentOf(threshold, req.Salt, req.Direction)

	e.mu.Lock()
	if existing, held := e.secrets[req.RuleID]; held && !strings.EqualFold(existing.account, req.Account) {
		e.mu.Unlock()
		// Refuse rather than overwrite: otherwise anyone who can reach the instruction sender could
		// replace another account's threshold and steer when their rule fires.
		return buildResult(action, df, nil, 0, fmt.Errorf("rule %d already provisioned by another account", req.RuleID))
	}
	e.secrets[req.RuleID] = &secret{
		threshold:  threshold,
		commitment: c,
		direction:  req.Direction,
		account:    req.Account,
	}
	e.provisionsSeen++
	e.mu.Unlock()

	data, _ := json.Marshal(types.ProvisionResponse{
		RuleID:     req.RuleID,
		Commitment: c.Hex(),
		Stored:     true,
	})
	return buildResult(action, df, data, 1, nil)
}

// processEvaluate answers "should rule N fire at this price?" and nothing else.
func (e *Extension) processEvaluate(action teetypes.Action, df *instruction.DataFixed) teetypes.ActionResult {
	var req types.EvaluateRequest
	dec := json.NewDecoder(bytes.NewReader(df.OriginalMessage))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&req); err != nil {
		return buildResult(action, df, nil, 0, fmt.Errorf("decoding evaluate request: %w", err))
	}

	observed, ok := new(big.Int).SetString(strings.TrimSpace(req.ObservedPrice), 10)
	if !ok || observed.Sign() <= 0 {
		return buildResult(action, df, nil, 0, fmt.Errorf("observedPrice must be a positive decimal integer"))
	}

	e.mu.Lock()
	s, held := e.secrets[req.RuleID]
	if !held {
		e.mu.Unlock()
		// Rule 7, inherited from Plimsoll: unknown means do not execute. A missing secret is not
		// "assume it fires"; it is a refusal. A restart wipes enclave memory, and the correct
		// response to that is to stop firing, not to guess.
		return buildResult(action, df, nil, 0, fmt.Errorf("no secret held for rule %d; re-provision it", req.RuleID))
	}

	var fire bool
	switch s.direction {
	case types.DirectionBelow:
		fire = observed.Cmp(s.threshold) <= 0
	case types.DirectionAbove:
		fire = observed.Cmp(s.threshold) >= 0
	}

	e.evaluations++
	if fire {
		e.firedVerdicts++
	}
	e.lastEvaluated = time.Now().Unix()
	commitment := s.commitment
	e.mu.Unlock()

	// The response carries the verdict, the commitment, the nonce and the time. It carries nothing
	// from which the threshold could be recovered — no distance, no bounds, no comparison margin.
	data, _ := json.Marshal(types.EvaluateResponse{
		RuleID:     req.RuleID,
		Fire:       fire,
		Commitment: commitment.Hex(),
		Nonce:      req.Nonce,
		IssuedAt:   time.Now().Unix(),
	})
	return buildResult(action, df, data, 1, nil)
}

// processForget drops a secret. A user who cancels a rule should not have to trust that we stopped
// holding their threshold — they can make us drop it and see the count fall on /state.
func (e *Extension) processForget(action teetypes.Action, df *instruction.DataFixed) teetypes.ActionResult {
	var req types.ForgetRequest
	dec := json.NewDecoder(bytes.NewReader(df.OriginalMessage))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&req); err != nil {
		return buildResult(action, df, nil, 0, fmt.Errorf("decoding forget request: %w", err))
	}

	e.mu.Lock()
	s, held := e.secrets[req.RuleID]
	if held && !strings.EqualFold(s.account, req.Account) {
		e.mu.Unlock()
		return buildResult(action, df, nil, 0, fmt.Errorf("rule %d belongs to another account", req.RuleID))
	}
	delete(e.secrets, req.RuleID)
	e.mu.Unlock()

	data, _ := json.Marshal(types.ForgetResponse{RuleID: req.RuleID, Existed: held})
	return buildResult(action, df, data, 1, nil)
}
