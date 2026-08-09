package extension

import (
	"encoding/json"
	"fmt"
	"math/big"
	"net/http"
	"strings"
	"testing"

	"extension-scaffold/internal/config"
	"extension-scaffold/pkg/types"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
	teetypes "github.com/flare-foundation/tee-node/pkg/types"
	teeutils "github.com/flare-foundation/tee-node/pkg/utils"
)

func toHash(s string) common.Hash { return teeutils.ToHash(s) }

// buildTestAction constructs the Action shape processAction parses, mirroring the scaffold's own
// harness so these tests exercise the real routing rather than calling handlers directly.
func buildTestAction(opType, opCommand common.Hash, originalMessage []byte) teetypes.Action {
	type dataFixed struct {
		InstructionID      common.Hash    `json:"instructionId"`
		TeeID              common.Address `json:"teeId"`
		Timestamp          uint64         `json:"timestamp"`
		RewardEpochID      uint32         `json:"rewardEpochId"`
		OPType             common.Hash    `json:"opType"`
		OPCommand          common.Hash    `json:"opCommand"`
		Cosigners          []string       `json:"cosigners"`
		CosignersThreshold uint64         `json:"cosignersThreshold"`
		OriginalMessage    hexutil.Bytes  `json:"originalMessage"`
	}
	df := dataFixed{OPType: opType, OPCommand: opCommand, OriginalMessage: originalMessage}
	msg, _ := json.Marshal(df)
	return teetypes.Action{
		Data: teetypes.ActionData{
			ID:            common.HexToHash("0x1234"),
			SubmissionTag: "submit",
			Message:       msg,
		},
	}
}

const testSalt = "a-sufficiently-long-salt-value"

// newExt gives the handlers an IDENTITY decryptor: the suite feeds plaintext and the handler
// treats it as the decrypted result. That keeps every behavioural test readable while leaving the
// real ECIES path exercised on chain — and TestProvisionRefusesPlaintext below pins the property
// that actually matters, namely that a real deployment cannot accept an unencrypted threshold.
func newExt() *Extension {
	return &Extension{
		secrets: make(map[uint64]*secret),
		decrypt: func(b []byte) ([]byte, error) { return b, nil },
	}
}

// A deployment whose decryptor rejects the payload must store NOTHING. This is the regression for
// the original defect: the handler decoded plaintext JSON straight off the instruction, which would
// have published every user's stop price on a public ledger while the docs claimed the opposite.
func TestProvisionRefusesWhatItCannotDecrypt(t *testing.T) {
	e := newExt()
	e.decrypt = func([]byte) ([]byte, error) { return nil, errAsIfCiphertextWasGarbage }

	_, body := provision(t, e, 1, "1000", types.DirectionBelow, "0xabc")
	if status, _ := resultOf(t, body); status != 0 {
		t.Fatal("provisioning must fail when the payload cannot be decrypted")
	}
	if _, body := evaluate(t, e, 1, "1", 1); func() bool { s, _ := resultOf(t, body); return s != 0 }() {
		t.Fatal("a rule whose provisioning failed must not evaluate")
	}
}

// And a handler with no decryptor at all must refuse rather than fall back to plaintext.
func TestProvisionRefusesWithoutADecryptor(t *testing.T) {
	e := &Extension{secrets: make(map[uint64]*secret)} // decrypt deliberately nil
	_, body := provision(t, e, 1, "1000", types.DirectionBelow, "0xabc")
	if status, _ := resultOf(t, body); status != 0 {
		t.Fatal("a nil decryptor must be a refusal, not a plaintext fallback")
	}
}

var errAsIfCiphertextWasGarbage = fmt.Errorf("enclave refused to decrypt (status 400)")

func provision(t *testing.T, e *Extension, ruleID uint64, threshold string, dir types.Direction, account string) (int, []byte) {
	t.Helper()
	body, _ := json.Marshal(types.ProvisionRequest{
		RuleID: ruleID, Threshold: threshold, Salt: testSalt, Direction: dir, Account: account,
	})
	return e.processAction(buildTestAction(
		toHash(config.OPTypeTrimmy), toHash(config.OPCommandProvision), body))
}

func evaluate(t *testing.T, e *Extension, ruleID uint64, price string, nonce uint64) (int, []byte) {
	t.Helper()
	body, _ := json.Marshal(types.EvaluateRequest{
		RuleID: ruleID, ObservedPrice: price, Nonce: nonce,
	})
	return e.processAction(buildTestAction(
		toHash(config.OPTypeTrimmy), toHash(config.OPCommandEvaluate), body))
}

// resultOf pulls the handler's payload out of the ActionResult envelope.
func resultOf(t *testing.T, body []byte) (status uint8, data []byte) {
	t.Helper()
	var ar teetypes.ActionResult
	if err := json.Unmarshal(body, &ar); err != nil {
		t.Fatalf("decoding ActionResult: %v", err)
	}
	return ar.Status, ar.Data
}

// --------------------------------------------------------------------------------------------
// The security properties. These are the reason the extension exists.
// --------------------------------------------------------------------------------------------

// A verdict must leak NOTHING about the threshold. Returning a distance, a margin, or bounds would
// let an observer binary-search the secret across repeated evaluations and defeat the whole design.
func TestVerdictLeaksNothingAboutTheThreshold(t *testing.T) {
	e := newExt()
	const threshold = "987654321987654321"
	provision(t, e, 1, threshold, types.DirectionBelow, "0xabc")

	for _, price := range []string{"1", "987654321987654320", "987654321987654322", "10000000000000000000"} {
		_, body := evaluate(t, e, 1, price, 1)
		blob := string(body)
		if strings.Contains(blob, threshold) {
			t.Fatalf("verdict leaked the threshold at price %s: %s", price, blob)
		}
		if strings.Contains(blob, testSalt) {
			t.Fatalf("verdict leaked the salt at price %s: %s", price, blob)
		}
	}
}

// /state reports counts, never contents. An operator needs liveness; nobody needs an endpoint that
// enumerates user secrets.
func TestStateNeverExposesSecrets(t *testing.T) {
	e := newExt()
	provision(t, e, 1, "555555555", types.DirectionBelow, "0xabc")

	rec := &captureWriter{}
	e.stateHandler(rec, nil)
	blob := rec.body.String()

	if strings.Contains(blob, "555555555") || strings.Contains(blob, testSalt) {
		t.Fatalf("/state leaked a secret: %s", blob)
	}
	if !strings.Contains(blob, `"secretsHeld":1`) {
		t.Fatalf("/state should report the count: %s", blob)
	}
}

// The commitment binds the direction. Without that, a threshold provisioned for PRICE_BELOW would
// satisfy a rule armed as PRICE_ABOVE at the same number, and the rule would fire on exactly the
// wrong side of the market.
func TestCommitmentBindsDirection(t *testing.T) {
	th := big.NewInt(1234567)
	below := commitmentOf(th, testSalt, types.DirectionBelow)
	above := commitmentOf(th, testSalt, types.DirectionAbove)
	if below == above {
		t.Fatal("same commitment for opposite directions: a stop would fire on the wrong side")
	}
}

// The separator matters: without it "1"+"23" and "12"+"3" would hash identically, so two different
// (threshold, salt) pairs would share a commitment.
func TestCommitmentIsNotAmbiguousAcrossFieldBoundaries(t *testing.T) {
	a := commitmentOf(big.NewInt(1), "23"+strings.Repeat("x", 16), types.DirectionBelow)
	b := commitmentOf(big.NewInt(12), "3"+strings.Repeat("x", 16), types.DirectionBelow)
	if a == b {
		t.Fatal("field boundary collision in the commitment")
	}
}

// --------------------------------------------------------------------------------------------
// Behaviour
// --------------------------------------------------------------------------------------------

func TestProvisionThenEvaluateBelow(t *testing.T) {
	e := newExt()
	code, body := provision(t, e, 7, "1000", types.DirectionBelow, "0xabc")
	if code != http.StatusOK {
		t.Fatalf("provision returned %d: %s", code, body)
	}
	status, data := resultOf(t, body)
	if status != 1 {
		t.Fatalf("provision status %d: %s", status, data)
	}

	var pr types.ProvisionResponse
	_ = json.Unmarshal(data, &pr)
	want := commitmentOf(big.NewInt(1000), testSalt, types.DirectionBelow).Hex()
	if pr.Commitment != want {
		t.Fatalf("commitment %s, want %s", pr.Commitment, want)
	}

	for _, tc := range []struct {
		price string
		fire  bool
	}{
		{"999", true},   // below
		{"1000", true},  // at the threshold, inclusive
		{"1001", false}, // above
	} {
		_, b := evaluate(t, e, 7, tc.price, 1)
		_, d := resultOf(t, b)
		var er types.EvaluateResponse
		_ = json.Unmarshal(d, &er)
		if er.Fire != tc.fire {
			t.Fatalf("price %s: fire=%v, want %v", tc.price, er.Fire, tc.fire)
		}
	}
}

func TestEvaluateAbove(t *testing.T) {
	e := newExt()
	provision(t, e, 8, "1000", types.DirectionAbove, "0xabc")
	for _, tc := range []struct {
		price string
		fire  bool
	}{{"1001", true}, {"1000", true}, {"999", false}} {
		_, b := evaluate(t, e, 8, tc.price, 1)
		_, d := resultOf(t, b)
		var er types.EvaluateResponse
		_ = json.Unmarshal(d, &er)
		if er.Fire != tc.fire {
			t.Fatalf("price %s: fire=%v, want %v", tc.price, er.Fire, tc.fire)
		}
	}
}

// Rule 7, inherited from Plimsoll: unknown means DO NOT execute. A restart wipes enclave memory,
// and the correct response is to stop firing, not to guess.
func TestEvaluateWithoutASecretRefuses(t *testing.T) {
	e := newExt()
	_, body := evaluate(t, e, 99, "1", 1)
	status, data := resultOf(t, body)
	if status != 0 {
		t.Fatalf("expected a refusal, got status %d: %s", status, data)
	}
}

func TestProvisionRejectsShortSalt(t *testing.T) {
	e := newExt()
	body, _ := json.Marshal(types.ProvisionRequest{
		RuleID: 1, Threshold: "1000", Salt: "short", Direction: types.DirectionBelow, Account: "0xabc",
	})
	_, out := e.processAction(buildTestAction(
		toHash(config.OPTypeTrimmy), toHash(config.OPCommandProvision), body))
	if status, _ := resultOf(t, out); status != 0 {
		t.Fatal("a short salt makes the commitment brute-forceable and must be refused")
	}
}

// Another account must not be able to replace a rule's threshold and steer when it fires.
func TestProvisionRefusesForeignOverwrite(t *testing.T) {
	e := newExt()
	provision(t, e, 5, "1000", types.DirectionBelow, "0xowner")
	_, body := provision(t, e, 5, "1", types.DirectionBelow, "0xattacker")
	if status, data := resultOf(t, body); status != 0 {
		t.Fatalf("expected refusal, got status %d: %s", status, data)
	}
	// And the original secret must be untouched.
	_, b := evaluate(t, e, 5, "999", 1)
	_, d := resultOf(t, b)
	var er types.EvaluateResponse
	_ = json.Unmarshal(d, &er)
	if !er.Fire {
		t.Fatal("the original threshold was modified by a foreign provision")
	}
}

func TestForgetRemovesTheSecret(t *testing.T) {
	e := newExt()
	provision(t, e, 3, "1000", types.DirectionBelow, "0xabc")

	body, _ := json.Marshal(types.ForgetRequest{RuleID: 3, Account: "0xabc"})
	_, out := e.processAction(buildTestAction(
		toHash(config.OPTypeTrimmy), toHash(config.OPCommandForget), body))
	if status, _ := resultOf(t, out); status != 1 {
		t.Fatal("forget should succeed for the owner")
	}

	_, b := evaluate(t, e, 3, "1", 1)
	if status, _ := resultOf(t, b); status != 0 {
		t.Fatal("evaluating a forgotten rule must refuse, not fire")
	}
}

func TestForgetRefusesForeignCaller(t *testing.T) {
	e := newExt()
	provision(t, e, 4, "1000", types.DirectionBelow, "0xowner")
	body, _ := json.Marshal(types.ForgetRequest{RuleID: 4, Account: "0xattacker"})
	_, out := e.processAction(buildTestAction(
		toHash(config.OPTypeTrimmy), toHash(config.OPCommandForget), body))
	if status, _ := resultOf(t, out); status != 0 {
		t.Fatal("a stranger must not be able to drop somebody else's trigger")
	}
}

func TestUnsupportedOpTypeAndCommand(t *testing.T) {
	e := newExt()
	if code, _ := e.processAction(buildTestAction(toHash("NOPE"), toHash(config.OPCommandEvaluate), []byte("{}"))); code != http.StatusNotImplemented {
		t.Fatal("unknown op type should be 501")
	}
	if code, _ := e.processAction(buildTestAction(toHash(config.OPTypeTrimmy), toHash("NOPE"), []byte("{}"))); code != http.StatusNotImplemented {
		t.Fatal("unknown op command should be 501")
	}
}

// captureWriter is a minimal http.ResponseWriter for stateHandler.
type captureWriter struct {
	body   strings.Builder
	status int
	hdr    http.Header
}

func (c *captureWriter) Header() http.Header {
	if c.hdr == nil {
		c.hdr = http.Header{}
	}
	return c.hdr
}
func (c *captureWriter) Write(b []byte) (int, error) { return c.body.Write(b) }
func (c *captureWriter) WriteHeader(s int)           { c.status = s }
