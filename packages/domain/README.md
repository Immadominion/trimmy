# Trimmy domain rules

Pure, deterministic logic for canonical u64 amounts, explanatory scaled balances, time-bound eligibility evidence, immutable X subjects, unfunded invitations, reviewed quote validity and cash-flow-neutral season performance. No rule calls a provider or writes data.

`evaluateEligibility` accepts a trusted server-stored provider attestation. It checks its binding and validity; it does not verify signatures, KYC documents, or turn client JSON into trusted evidence. Database identity and evidence ownership must be enforced independently. Country formatting alone is not a country allowlist or eligibility approval.

`explanatoryScaledBalance` multiplies a decimal-text multiplier exactly for educational display. Actual Token-2022 conversions have chain-defined floating-point behavior, effective-time rules and rounding. Use audited/tested chain SDK conversions for live wallet display/input validation and raw integer amounts for transactions. Never derive a spend by reversing rounded screen text.

An invitation always has `funding: unfunded`. Accepting one confirms social intent only. These rules do not claim funds exist, tokens were delivered, or that a refund is available. Recipient subject is frozen after addressing; its handle snapshot can differ from the authenticated account's current handle.

`timeWeightedReturn` multiplies exact subperiod return factors. Split subperiods at every external deposit/withdrawal. Each opening is measured after the preceding flow; each closing before the next. Values use the same currency and pricing policy. Market gains/losses and execution fees affect return; external capital does not. Missing valuations, zero-opening periods and negative values require explicit treatment and are rejected. The pure function cannot detect a caller that supplies incorrect valuation boundaries.

Cross-currency pricing, time-effective corporate actions, unsupported mint extensions, live route semantics, persistence concurrency, proof verification and reconciliation remain integration work. See the tests for representative adversarial cases; passing these tests is not a security audit of a live product.
