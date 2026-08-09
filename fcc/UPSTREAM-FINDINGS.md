# fce-extension-scaffold / fce-sign — verified defects

**Date:** 2026-08-07. Verified against `main` as cloned today, not against a report.

A participant in the Summer Signal Telegram reported three defects. **Two reproduce, one does not.**
Repeating the third would have meant submitting a patch for a bug that is not there, so it is
recorded here as refuted rather than fixed.

---

## D1 — `tee-node` is pinned below the stated minimum. Reproduces, in both repos.

```
fce-extension-scaffold/go/go.mod:8     github.com/flare-foundation/tee-node v0.0.21-0.20260619120252-31fc839ae6d2
fce-extension-scaffold/tools/go.mod:8  github.com/flare-foundation/tee-node v0.0.21-0.20260619120252-31fc839ae6d2
fce-sign/go/go.mod:9                   github.com/flare-foundation/tee-node v0.0.21-0.20260619120252-31fc839ae6d2
```

`[Verified]` The pin is a pseudo-version of **v0.0.21**, below the documented v0.0.22 minimum.

**Correction to the report:** it proposed bumping to `v0.0.24`. The current release is **v0.0.25** —
confirmed against both the GitHub tag list and `proxy.golang.org/.../@v/list`. Bumping to v0.0.24
would land one release stale on day one.

**Patch:** set all three `go.mod` files to `v0.0.25` and `go mod tidy`.

---

## D2 — `post-build.sh` omits `-command rRap`. Reproduces in the scaffold ONLY.

`fce-extension-scaffold/scripts/post-build.sh:148` invokes:

```bash
go run ./cmd/register-tee \
    -a "$ADDRESSES_FILE" -c "$CHAIN_URL" -p "$EXT_PROXY_URL" \
    -h "${EXT_PROXY_HOST_URL:-$EXT_PROXY_URL}" -ep "$NORMAL_PROXY_URL" \
    -state "$PROJECT_DIR/config/register-tee.state" \
    || die "Register TEE failed"
```

No `-command rRap`, so it defaults to `rap` and re-runs hit `Verification.ChallengeExpired`.

Two things make this worth upstreaming rather than working around:

1. **The fix already exists in the sibling repo.** `fce-sign/scripts/post-build.sh:144` *does* pass
   `-command rRap`. It simply was not ported back to the scaffold — which is the repo new builders
   start from.
2. **The docs know.** `docs/deployment-steps.md:192` carries a `> [!WARNING]` telling the reader to
   edit the script themselves before running it, and then reproduces the corrected block verbatim.
   A documented instruction to hand-patch a shipped script is a defect with a paper trail.

**Patch:** add `-command rRap \` to the scaffold's `post-build.sh` and delete the warning block from
`deployment-steps.md`, since it then describes what the script already does.

---

## D3 — "proxy `.toml` ships only as `.example`". **Does not reproduce.**

The report says `config/proxy/extension_proxy.coston2.docker.toml` exists only as `.example`, so
`docker compose up` bind-mounts a missing path, silently creates a directory in its place, and fails
with a confusing rootfs mount error.

`[Verified]` The first half is true — that file does ship only as `.example`. But it is **not what
docker-compose mounts**:

```
fce-extension-scaffold/docker-compose.yaml:13
  - ./config/proxy/extension_proxy.docker.toml:/app/config/config.toml:ro
fce-sign/docker-compose.yaml:27
  - ./config/proxy/extension_proxy.docker.toml:/app/config/config.toml:ro
```

and `extension_proxy.docker.toml` **exists** in both repos, without an `.example` suffix.

So the failure is real for anyone who switches the mount to the chain-specific config, but the
default path a new builder follows does not hit it. Not submitted as a patch.

`[Unverified]` Whether some script rewrites that mount for the coston2 path — `use-chain.sh` contains
no reference to the proxy toml, so nothing found so far does.

---

## Why this matters beyond the fixes

D1 and D2 both cost a real participant time, and D2's fix was already written and sitting in a
sibling repository. That is a small, well-evidenced contribution to make.

D3 is the more useful lesson for us: the report was 2/3 right, and repeating the third without
checking would have put a wrong patch in front of the maintainers under our name.
