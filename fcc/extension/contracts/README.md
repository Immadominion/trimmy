# Contracts for the confidential-trigger extension

`TrimmyConfidentialTrigger.sol` — the InstructionSender and verdict verifier — lives at
[`../../../contracts/src/TrimmyConfidentialTrigger.sol`](../../../contracts/src/TrimmyConfidentialTrigger.sol),
not here.

It is a Trimmy contract: Trimmy's deploy scripts deploy it, Trimmy's suite tests it, and Trimmy's
`execute()` calls its `consumeVerdict`. Keeping it in one Solidity workspace means one toolchain,
one lint gate and one test run, rather than two that can drift.

What stays here is the extension's own code — the Go handlers in `../go/`, whose
`internal/config/config.go` OPType and OPCommand constants **must match that contract byte for
byte**. A mismatch falls through to "unsupported op type" and is silent from the caller's side, so
the two files are cross-referenced in each other's comments.
