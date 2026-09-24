#!/usr/bin/env bash
set -euo pipefail

infra_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_dir="$(cd "$infra_dir/.." && pwd)"
runtime_dir="$infra_dir/.practice-runtime"
postgres_bin="${TRIMMY_POSTGRES_BIN:-}"
if [[ -z "$postgres_bin" ]]; then
  if command -v pg_config >/dev/null 2>&1; then
    postgres_bin="$(pg_config --bindir)"
  else
    echo 'Set TRIMMY_POSTGRES_BIN to an installed PostgreSQL bin directory.' >&2
    exit 1
  fi
fi
for executable in initdb pg_ctl psql; do
  [[ -x "$postgres_bin/$executable" ]] || { echo "Missing binary: $executable" >&2; exit 1; }
done
[[ ${#runtime_dir} -le 80 ]] || { echo 'Checkout path is too long for private PostgreSQL sockets.' >&2; exit 1; }
(umask 077 && mkdir "$runtime_dir") || { echo 'Practice test runtime already exists; inspect before retrying.' >&2; exit 1; }
started=0
cleanup() {
  result=$?
  if [[ $started -eq 1 ]]; then
    if ! "$postgres_bin/pg_ctl" -D "$runtime_dir/data" -m fast -w stop >/dev/null; then
      echo 'Could not stop the test cluster. Runtime retained for inspection.' >&2
      exit 1
    fi
  fi
  if [[ $result -ne 0 ]]; then
    [[ ! -f "$runtime_dir/postgres.log" ]] || tail -n 100 "$runtime_dir/postgres.log" >&2
  fi
  rm -rf -- "$runtime_dir"
  exit "$result"
}
trap cleanup EXIT
mkdir "$runtime_dir/socket"
chmod 700 "$runtime_dir/socket"
"$postgres_bin/initdb" -D "$runtime_dir/data" -A trust --no-locale -E UTF8 -U trimmy_test_owner >"$runtime_dir/init.log"
"$postgres_bin/pg_ctl" -D "$runtime_dir/data" -l "$runtime_dir/postgres.log" \
  -o "-c listen_addresses='' -c unix_socket_directories='$runtime_dir/socket' -c port=65438" -w start >/dev/null
started=1
psql_args=(-X -v ON_ERROR_STOP=1 -h "$runtime_dir/socket" -p 65438 -U trimmy_test_owner -d postgres)
for migration in 0001_foundation 0002_practice_progress 0003_practice_accounts 0004_watchlists; do
  "$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/$migration.sql" >"$runtime_dir/$migration.log"
done
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/tests/practice-v4-before-migration.sql" >"$runtime_dir/v4-before-migration.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/0005_practice_payload_v4.sql" >"$runtime_dir/0005_practice_payload_v4.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/tests/practice-fixtures.sql" >"$runtime_dir/fixtures.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/tests/practice-constraints.sql" >"$runtime_dir/constraints.log"
tail -n 6 "$runtime_dir/constraints.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/tests/practice-account-constraints.sql" >"$runtime_dir/account-constraints.log"
tail -n 6 "$runtime_dir/account-constraints.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/tests/watchlist-constraints.sql" >"$runtime_dir/watchlist-constraints.log"
tail -n 6 "$runtime_dir/watchlist-constraints.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/tests/practice-v4-constraints.sql" >"$runtime_dir/v4-constraints.log"
tail -n 6 "$runtime_dir/v4-constraints.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/tests/practice-v5-before-migration.sql" >"$runtime_dir/v5-before-migration.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/0006_practice_payload_v5.sql" >"$runtime_dir/0006_practice_payload_v5.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/tests/practice-v5-constraints.sql" >"$runtime_dir/v5-constraints.log"
tail -n 6 "$runtime_dir/v5-constraints.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/0007_wallet_possession_and_reviews.sql" >"$runtime_dir/0007_wallet_possession_and_reviews.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/tests/wallet-review-fixtures.sql" >"$runtime_dir/wallet-review-fixtures.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/tests/wallet-review-constraints.sql" >"$runtime_dir/wallet-review-constraints.log"
tail -n 6 "$runtime_dir/wallet-review-constraints.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/0008_practice_payload_v6.sql" >"$runtime_dir/0008_practice_payload_v6.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/tests/practice-v6-constraints.sql" >"$runtime_dir/v6-constraints.log"
tail -n 6 "$runtime_dir/v6-constraints.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/0009_invitations.sql" >"$runtime_dir/0009_invitations.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/tests/invitation-fixtures.sql" >"$runtime_dir/invitation-fixtures.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/0010_account_closure.sql" >"$runtime_dir/0010_account_closure.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/tests/closure-fixtures.sql" >"$runtime_dir/closure-fixtures.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/0011_wallet_possession_challenges.sql" >"$runtime_dir/0011_wallet_possession_challenges.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/tests/wallet-challenge-fixtures.sql" >"$runtime_dir/wallet-challenge-fixtures.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/0012_followed_stocks.sql" >"$runtime_dir/0012_followed_stocks.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/tests/followed-stock-fixtures.sql" >"$runtime_dir/followed-stock-fixtures.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/0013_paper_trading.sql" >"$runtime_dir/0013_paper_trading.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/0014_guest_sessions.sql" >"$runtime_dir/0014_guest_sessions.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/0015_product_profiles.sql" >"$runtime_dir/0015_product_profiles.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/0016_guest_creation_idempotency.sql" >"$runtime_dir/0016_guest_creation_idempotency.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/0017_career_core.sql" >"$runtime_dir/0017_career_core.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/tests/career-0018-before-migration.sql" >"$runtime_dir/career-0018-before-migration.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/0018_career_missions_and_promotions.sql" >"$runtime_dir/0018_career_missions_and_promotions.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/0019_career_local_day.sql" >"$runtime_dir/0019_career_local_day.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/0020_guest_creation_abuse_and_retention.sql" >"$runtime_dir/0020_guest_creation_abuse_and_retention.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/0021_career_red_day_evidence.sql" >"$runtime_dir/0021_career_red_day_evidence.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/0022_product_launch_evidence.sql" >"$runtime_dir/0022_product_launch_evidence.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/0023_paper_reset.sql" >"$runtime_dir/0023_paper_reset.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/0024_career_reason_sharing.sql" >"$runtime_dir/0024_career_reason_sharing.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/0025_relationship_safety.sql" >"$runtime_dir/0025_relationship_safety.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/0026_optional_introduction.sql" >"$runtime_dir/0026_optional_introduction.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/0027_career_activity_week.sql" >"$runtime_dir/0027_career_activity_week.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/tests/paper-trading-fixtures.sql" >"$runtime_dir/paper-trading-fixtures.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/tests/guest-session-fixtures.sql" >"$runtime_dir/guest-session-fixtures.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/tests/product-profile-fixtures.sql" >"$runtime_dir/product-profile-fixtures.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/tests/product-launch-fixtures.sql" >"$runtime_dir/product-launch-fixtures.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/tests/career-fixtures.sql" >"$runtime_dir/career-fixtures.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/tests/relationship-integration-fixtures.sql" >"$runtime_dir/relationship-integration-fixtures.log"
export TRIMMY_PRACTICE_TEST_SOCKET="$runtime_dir/socket"
export TRIMMY_PRACTICE_TEST_PORT=65438
cd "$project_dir"
npm run build:backend
node --import tsx --test apps/api/test/integration/practice-postgres.test.ts
node --import tsx --test apps/api/test/integration/practice-v4-postgres.test.ts
node --import tsx --test apps/api/test/integration/practice-v5-postgres.test.ts
node --import tsx --test apps/api/test/integration/practice-accounts-postgres.test.ts
node --import tsx --test apps/api/test/integration/watchlist-postgres.test.ts
node --import tsx --test apps/api/test/integration/wallet-review-postgres.test.ts
node --import tsx --test apps/api/test/integration/invitations-postgres.test.ts
node --import tsx --test apps/api/test/integration/account-closure-postgres.test.ts
node --import tsx --test apps/api/test/integration/readiness-postgres.test.ts
node --import tsx --test apps/api/test/integration/wallet-challenges-postgres.test.ts
node --import tsx --test apps/api/test/integration/followed-stocks-postgres.test.ts
node --import tsx --test apps/api/test/integration/paper-trading-postgres.test.ts
node --import tsx --test apps/api/test/integration/guest-session-postgres.test.ts
node --import tsx --test apps/api/test/integration/product-profile-postgres.test.ts
node --import tsx --test apps/api/test/integration/career-postgres.test.ts
node --import tsx --test apps/web/test/integration/watchlist-api.test.ts
if [[ "${TRIMMY_PRACTICE_TEST_MOBILE:-0}" = '1' ]]; then
  node --import tsx apps/api/test/integration/run-mobile-sync.ts
fi
# Shut down and restart the same exclusively owned cluster, then re-open the
# API/repository and retry a mutation committed by the first process.
"$postgres_bin/pg_ctl" -D "$runtime_dir/data" -m fast -w stop >/dev/null
started=0
"$postgres_bin/pg_ctl" -D "$runtime_dir/data" -l "$runtime_dir/postgres.log" \
  -o "-c listen_addresses='' -c unix_socket_directories='$runtime_dir/socket' -c port=65438" -w start >/dev/null
started=1
TRIMMY_PRACTICE_TEST_RECOVERY=1 node --import tsx --test apps/api/test/integration/practice-postgres.test.ts
TRIMMY_PRACTICE_TEST_RECOVERY=1 node --import tsx --test apps/api/test/integration/watchlist-postgres.test.ts
TRIMMY_PRACTICE_TEST_RECOVERY=1 node --import tsx --test apps/api/test/integration/wallet-review-postgres.test.ts
TRIMMY_PRACTICE_TEST_RECOVERY=1 node --import tsx --test apps/api/test/integration/practice-v4-postgres.test.ts
TRIMMY_PRACTICE_TEST_RECOVERY=1 node --import tsx --test apps/api/test/integration/practice-v5-postgres.test.ts
TRIMMY_PRACTICE_TEST_RECOVERY=1 node --import tsx --test apps/api/test/integration/paper-trading-postgres.test.ts
TRIMMY_PRACTICE_TEST_RECOVERY=1 node --import tsx --test apps/api/test/integration/guest-session-postgres.test.ts
TRIMMY_PRACTICE_TEST_RECOVERY=1 node --import tsx --test apps/api/test/integration/product-profile-postgres.test.ts
TRIMMY_PRACTICE_TEST_RECOVERY=1 node --import tsx --test apps/api/test/integration/career-postgres.test.ts
"$postgres_bin/psql" "${psql_args[@]}" -Atc 'SELECT version()'
echo 'PASS: practice SQL, authenticated API/database integration and restart recovery; private cluster will be removed.'
