// Package config holds the operation identifiers that bind the Solidity contract to this
// extension's handlers, plus the version reported by /state.
//
// These strings MUST match, byte for byte, across three layers:
//
//	Solidity   bytes32 OP_TYPE_TRIMMY = bytes32("TRIMMY")
//	Go config  OPTypeTrimmy = "TRIMMY"          <- here
//	Go router  dataFixed.OPType == teeutils.ToHash(config.OPTypeTrimmy)
//
// A mismatched OPType falls through to "unsupported op type" and a mismatched OPCommand to
// "unsupported op command" — both silent from the caller's point of view, which is why they are
// defined once, here, and referenced everywhere else.
//
// bytes32("...") holds at most 31 bytes, so identifiers stay short.
package config

import (
	"os"
	"strconv"
	"time"
)

const (
	Version = "trimmy-confidential-trigger/0.1.0"

	// OPTypeTrimmy groups every Trimmy confidential-trigger operation.
	OPTypeTrimmy = "TRIMMY"

	// OPCommandProvision stores a rule's SECRET threshold inside the enclave.
	//
	// The payload arrives ECIES-encrypted to the enclave's public key, so the threshold is never
	// legible on chain — only the ciphertext and the commitment are. This is the whole point of
	// the extension: `Trimmy.triggerValue` is public for an ordinary rule, and publishing a stop
	// price tells every observer exactly when a large, price-insensitive sell will arrive.
	OPCommandProvision = "PROVISION"

	// OPCommandEvaluate asks the enclave whether a rule's secret condition is met right now, and
	// returns a signed verdict the contract can verify with ecrecover.
	OPCommandEvaluate = "EVALUATE"

	// OPCommandForget removes a rule's secret. A user who cancels a rule should not have to trust
	// that we stopped holding their threshold.
	OPCommandForget = "FORGET"
)

const (
	// TimeoutShutdown is the grace period main() gives the HTTP server.
	TimeoutShutdown = 5 * time.Second

	// MaxVerdictAgeSeconds bounds how long a signed verdict remains usable on chain.
	//
	// It exists because the verdict is the ONE part of a confidential rule that the permissionless
	// path cannot re-derive. Every other bound in Trimmy.execute is recomputed on chain from live
	// FTSO; this one is asserted by an enclave at a point in time. A stale verdict is therefore a
	// stale price by another route, so it is bounded by the same reasoning that set maxFeedAge to
	// 64 s — 2x the measured max-of-p99 feed age — and rounded up to leave room for one round trip.
	MaxVerdictAgeSeconds = 90
)

// Ports. Defaults, overridden by the environment the TEE node provides.
//
// Kept as the scaffold declares them — `ExtensionPort`, `SignPort`, and the `init()` override —
// because `cmd/main.go` is boilerplate we do not modify, and renaming them here would be a
// gratuitous divergence from upstream that every future scaffold bump would have to re-merge.
var (
	ExtensionPort = 8080
	SignPort      = 9090
)

func init() {
	if ep := os.Getenv("EXTENSION_PORT"); ep != "" {
		if v, err := strconv.Atoi(ep); err == nil {
			ExtensionPort = v
		}
	}
	if sp := os.Getenv("SIGN_PORT"); sp != "" {
		if v, err := strconv.Atoi(sp); err == nil {
			SignPort = v
		}
	}
}
