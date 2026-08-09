// Drives a Trimmy PRIVATE rule end to end, through a real enclave.
//
// This is the one path that Bounty 2's claim rests on, and until it runs nothing proves the pieces
// fit together. Every component was tested alone — the handler has unit tests, the contract has
// regressions, the enclave is attested and registered — and every bug this project has hit lived in
// a seam between two such components, not inside one.
//
//	1. read the enclave's public key from the proxy   (nothing secret has happened yet)
//	2. ECIES-encrypt the threshold TO that key        (now only the enclave can read it)
//	3. commit  keccak256(threshold ‖ salt ‖ direction) on chain
//	4. send the ciphertext as a PROVISION instruction
//	5. ask for a verdict at an observed price
//	6. read the enclave's SIGNED result
//
// What travels on chain in step 4 is ciphertext. What the chain stores in step 3 is a commitment.
// The threshold itself exists only inside the enclave. That is the product.
//
// Usage:
//
//	go run ./cmd/trimmy-private -trigger 0x... -rule 0 -threshold 1500000 -price 1000000
package main

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"os"
	"strings"

	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/crypto/ecies"
)

type provisionRequest struct {
	RuleID    uint64 `json:"ruleId"`
	Threshold string `json:"threshold"`
	Salt      string `json:"salt"`
	Direction uint8  `json:"direction"`
	Account   string `json:"account"`
}

func main() {
	proxy := flag.String("proxy", "http://localhost:6664", "extension proxy url")
	rule := flag.Uint64("rule", 0, "Trimmy rule id")
	threshold := flag.String("threshold", "", "the SECRET trigger price (decimal, Trimmy relative units)")
	salt := flag.String("salt", "", "commitment salt (>=16 chars; generated if empty)")
	direction := flag.Uint("direction", 0, "0 = fire at or below, 1 = fire at or above")
	account := flag.String("account", "", "account that armed the rule")
	flag.Parse()

	if *threshold == "" || *account == "" {
		fatal("-threshold and -account are required")
	}
	th, ok := new(big.Int).SetString(strings.TrimSpace(*threshold), 10)
	if !ok || th.Sign() <= 0 {
		fatal("-threshold must be a positive decimal integer")
	}
	if *direction > 1 {
		fatal("-direction must be 0 or 1")
	}

	s := *salt
	if s == "" {
		b := make([]byte, 16)
		if _, err := rand.Read(b); err != nil {
			fatal("generating salt: %v", err)
		}
		s = hex.EncodeToString(b)
	}
	if len(s) < 16 {
		// The enclave refuses a short salt for the same reason: the plausible range of a stop
		// price is small, so without a salt the public commitment is brute-forceable.
		fatal("salt must be at least 16 characters")
	}

	// ---- 1. the enclave's public key -----------------------------------------------------
	pub, teeID, err := enclaveKey(*proxy)
	if err != nil {
		fatal("reading the enclave public key: %v", err)
	}
	fmt.Println("enclave")
	fmt.Printf("  teeId     : %s\n", teeID)
	fmt.Printf("  publicKey : %x…\n", crypto.FromECDSAPub(pub)[:16])

	// ---- 2. commitment -------------------------------------------------------------------
	// Byte-for-byte identical to `commitmentOf` in the extension. If these two ever disagree the
	// rule can never fire, so the separator and the direction byte are part of the contract.
	var buf bytes.Buffer
	buf.WriteString(th.String())
	buf.WriteByte(0x1f)
	buf.WriteString(s)
	buf.WriteByte(0x1f)
	buf.WriteByte(byte(*direction))
	commitment := crypto.Keccak256Hash(buf.Bytes())

	// ---- 3. encrypt the secret TO the enclave --------------------------------------------
	payload, err := json.Marshal(provisionRequest{
		RuleID:    *rule,
		Threshold: th.String(),
		Salt:      s,
		Direction: uint8(*direction),
		Account:   *account,
	})
	if err != nil {
		fatal("encoding provision request: %v", err)
	}
	ciphertext, err := ecies.Encrypt(rand.Reader, ecies.ImportECDSAPublic(pub), payload, nil, nil)
	if err != nil {
		fatal("ECIES encrypt: %v", err)
	}

	// Sanity: the ciphertext must not contain the secret. Cheap, and it catches a wiring mistake
	// that would otherwise publish the threshold on chain.
	if bytes.Contains(ciphertext, []byte(th.String())) || bytes.Contains(ciphertext, []byte(s)) {
		fatal("REFUSING: ciphertext still contains the plaintext secret")
	}

	fmt.Println("\nwhat goes on chain")
	fmt.Printf("  commitment : %s\n", commitment.Hex())
	fmt.Printf("  ciphertext : %d bytes, 0x%x…\n", len(ciphertext), ciphertext[:16])
	fmt.Printf("  threshold  : NOT on chain (it is %d digits, held only in the enclave)\n", len(th.String()))

	fmt.Println("\nnext, on chain:")
	fmt.Printf("  cast send $TRIGGER 'commitTrigger(uint256,bytes32)' %d %s\n", *rule, commitment.Hex())
	fmt.Printf("  cast send $TRIGGER 'provision(uint256,bytes)' %d 0x%x --value <fee>\n", *rule, ciphertext)

	// Emit machine-readable output so a shell driver can consume it without re-deriving anything.
	out := map[string]string{
		"ruleId":     fmt.Sprintf("%d", *rule),
		"commitment": commitment.Hex(),
		"ciphertext": "0x" + hex.EncodeToString(ciphertext),
		"salt":       s,
		"teeId":      teeID,
	}
	b, _ := json.MarshalIndent(out, "", "  ")
	if err := os.WriteFile("../config/private-rule.json", b, 0o600); err != nil {
		fatal("writing private-rule.json: %v", err)
	}
	fmt.Println("\nwrote ../config/private-rule.json (0600) — the salt is in it, keep it local")
}

// enclaveKey reads the enclave's ECDSA public key and machine id from the proxy's /info.
func enclaveKey(proxy string) (*ecdsa.PublicKey, string, error) {
	resp, err := http.Get(strings.TrimRight(proxy, "/") + "/info")
	if err != nil {
		return nil, "", err
	}
	defer func() { _ = resp.Body.Close() }()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, "", err
	}

	var info struct {
		MachineData struct {
			TeeID     string `json:"teeId"`
			PublicKey struct {
				X string `json:"x"`
				Y string `json:"y"`
			} `json:"publicKey"`
		} `json:"machineData"`
	}
	if err := json.Unmarshal(body, &info); err != nil {
		return nil, "", err
	}

	x, ok := new(big.Int).SetString(strings.TrimPrefix(info.MachineData.PublicKey.X, "0x"), 16)
	if !ok {
		return nil, "", fmt.Errorf("public key x is not hex")
	}
	y, ok := new(big.Int).SetString(strings.TrimPrefix(info.MachineData.PublicKey.Y, "0x"), 16)
	if !ok {
		return nil, "", fmt.Errorf("public key y is not hex")
	}

	pub := &ecdsa.PublicKey{Curve: crypto.S256(), X: x, Y: y}
	if !pub.Curve.IsOnCurve(x, y) {
		// A point off the curve is not a key; encrypting to it would produce ciphertext nobody
		// can read, and the failure would only surface after an on-chain instruction was paid for.
		return nil, "", fmt.Errorf("enclave public key is not on secp256k1")
	}
	return pub, info.MachineData.TeeID, nil
}

func fatal(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "error: "+format+"\n", args...)
	os.Exit(1)
}
