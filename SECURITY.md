# Security

Do not post secrets or customer data in a public issue. Use GitHub's private vulnerability reporting if it is enabled for this repository, or contact the maintainer privately first.

## Configuration boundary

- Server credentials belong in environment variables or private storage outside the repository.
- Flutter defines and Vite configuration are public client configuration. Never place a provider secret, private key, database password or authenticated RPC URL there.
- `production-config.json`, local config files, environment files, signing material, device logs and test output are excluded from version control.
- Crossmint staging credentials are test-environment credentials, not permission to expose them. Rotate credentials that have been shared outside their intended storage.
- Real/Paper mode is a UI selection, not an authorization boundary. Authentication, wallet binding, issuer eligibility and execution checks remain server responsibilities.

## Money and retries

Paper funds and wallet funds use separate order paths. An order-status timeout must not be interpreted as proof that a submitted transaction failed. Preserve the request identity and reconcile it before retrying. A staged checkout or quote is not evidence of a completed payment or trade.

## Publication checks

This repository has been checked for known credential values and common secret patterns before its initial publication. Narrow `gitleaks:allow` comments identify synthetic test tokens, public addresses and preference keys that were reviewed individually. A clean scan is not a security audit of the entire application or a guarantee that future commits are safe.
