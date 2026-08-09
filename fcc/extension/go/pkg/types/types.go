// Package types contains the request and response payloads exchanged with the Trimmy
// confidential-trigger extension. They are exported because the contract, the keeper and the
// types server all need to agree on them.
package types

// Direction mirrors Trimmy.Trigger for the two price directions. SCHEDULE has no secret to keep,
// so it never reaches the enclave.
type Direction uint8

const (
	DirectionBelow Direction = 0 // fire when the price is at or below the threshold
	DirectionAbove Direction = 1 // fire when the price is at or above the threshold
)

// ProvisionRequest carries a rule's secret threshold into the enclave.
//
// It arrives ECIES-encrypted to the enclave's public key. What reaches the chain is ciphertext plus
// the commitment; the threshold itself is never on chain, which is the entire reason this extension
// exists.
type ProvisionRequest struct {
	RuleID uint64 `json:"ruleId"`

	// Threshold is the secret trigger price, in the SAME units Trimmy uses: buy-token base units
	// per one whole sell token. Carried as a decimal string, never a float — mixing units or
	// losing precision here is the class of bug that costs users money silently.
	Threshold string `json:"threshold"`

	// Salt makes the commitment hiding. Without it a threshold is guessable by brute force: the
	// plausible range of a stop price is small and the hash is public.
	Salt string `json:"salt"`

	Direction Direction `json:"direction"`

	// Account that armed the rule. The enclave refuses to overwrite another account's secret.
	Account string `json:"account"`
}

// ProvisionResponse returns the commitment the enclave computed, so the caller can check it equals
// the one already stored in the rule. A mismatch means the rule and the secret disagree and the
// rule could never fire — better discovered now than at the moment it was meant to protect someone.
type ProvisionResponse struct {
	RuleID     uint64 `json:"ruleId"`
	Commitment string `json:"commitment"` // 0x-prefixed keccak256(threshold ‖ salt ‖ direction)
	Stored     bool   `json:"stored"`
}

// EvaluateRequest asks whether a rule's secret condition is met at a given observed price.
//
// The price is supplied by the caller rather than fetched here, and that is deliberate: it must be
// the SAME number the contract will re-derive from FTSO when it executes. An enclave that fetched
// its own price could disagree with the chain, and the disagreement would be invisible.
type EvaluateRequest struct {
	RuleID uint64 `json:"ruleId"`

	// ObservedPrice in Trimmy's relative units, as a decimal string.
	ObservedPrice string `json:"observedPrice"`

	// Nonce binds a verdict to one execution attempt so it cannot be replayed.
	Nonce uint64 `json:"nonce"`
}

// EvaluateResponse is the signed verdict.
//
// It deliberately does NOT include the threshold, the salt or how far the price is from firing.
// Returning a distance would leak the secret over repeated queries — an observer could binary-search
// the threshold by watching verdicts, which would defeat the whole design.
type EvaluateResponse struct {
	RuleID     uint64 `json:"ruleId"`
	Fire       bool   `json:"fire"`
	Commitment string `json:"commitment"`
	Nonce      uint64 `json:"nonce"`

	// IssuedAt is when the enclave formed this verdict. The contract rejects one older than
	// MaxVerdictAgeSeconds, because a stale verdict is a stale price by another route.
	IssuedAt int64 `json:"issuedAt"`
}

// ForgetRequest drops a rule's secret.
type ForgetRequest struct {
	RuleID  uint64 `json:"ruleId"`
	Account string `json:"account"`
}

// ForgetResponse reports whether anything was actually held.
type ForgetResponse struct {
	RuleID  uint64 `json:"ruleId"`
	Existed bool   `json:"existed"`
}

// State is what GET /state exposes for operational visibility.
//
// It reports COUNTS and never contents. An operator needs to know the extension is alive and how
// many secrets it holds; nobody — including us — needs an endpoint that lists them.
type State struct {
	Version         string `json:"version"`
	SecretsHeld     int    `json:"secretsHeld"`
	Evaluations     int    `json:"evaluations"`
	FiredVerdicts   int    `json:"firedVerdicts"`
	ProvisionsSeen  int    `json:"provisionsSeen"`
	LastEvaluatedAt int64  `json:"lastEvaluatedAt"`
}
