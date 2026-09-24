#!/usr/bin/env bash
# Isolated migration-0024 privacy, feed, RLS and restart harness.
set -euo pipefail

infra_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_dir="$(cd "$infra_dir/.." && pwd)"
runtime_dir="$infra_dir/.crs-runtime"
postgres_bin="${TRIMMY_POSTGRES_BIN:-}"
if [[ -z "$postgres_bin" ]]; then postgres_bin="$(pg_config --bindir)"; fi
for executable in initdb pg_ctl psql; do
  [[ -x "$postgres_bin/$executable" ]] \
    || { echo "Missing binary: $executable" >&2; exit 1; }
done
[[ ${#runtime_dir} -le 80 ]] \
  || { echo 'Checkout path is too long for private PostgreSQL sockets.' >&2; exit 1; }
(umask 077 && mkdir "$runtime_dir") \
  || { echo 'Career reason sharing runtime already exists; inspect before retrying.' >&2; exit 1; }
started=0
cleanup() {
  result=$?
  if [[ $started -eq 1 ]]; then
    "$postgres_bin/pg_ctl" -D "$runtime_dir/data" -m fast -w stop >/dev/null || true
  fi
  if [[ $result -ne 0 ]]; then
    [[ ! -f "$runtime_dir/postgres.log" ]] \
      || tail -n 80 "$runtime_dir/postgres.log" >&2
  fi
  python3 - "$runtime_dir" <<'PY'
from pathlib import Path
import shutil
import sys
path = Path(sys.argv[1])
if path.name == '.crs-runtime' and path.exists():
    shutil.rmtree(path)
PY
  exit "$result"
}
trap cleanup EXIT

mkdir "$runtime_dir/socket"
chmod 700 "$runtime_dir/socket"
"$postgres_bin/initdb" -D "$runtime_dir/data" -A trust --no-locale -E UTF8 \
  -U trimmy_reason_share_test_owner >"$runtime_dir/init.log"
"$postgres_bin/pg_ctl" -D "$runtime_dir/data" -l "$runtime_dir/postgres.log" \
  -o "-c listen_addresses='' -c unix_socket_directories='$runtime_dir/socket' -c port=65452" \
  -w start >/dev/null
started=1
owner_psql=("$postgres_bin/psql" -X -v ON_ERROR_STOP=1 -h "$runtime_dir/socket" \
  -p 65452 -U trimmy_reason_share_test_owner -d postgres)

for migration in "$infra_dir"/migrations/*.sql; do
  [[ "$(basename "$migration")" == '0024_career_reason_sharing.sql' ]] && break
  "${owner_psql[@]}" -f "$migration" >/dev/null
done

# This account proves the migration backfill. Accounts created by the tests
# after 0024 prove the future-user trigger.
"${owner_psql[@]}" -c \
  "INSERT INTO trimmy.users(id) VALUES ('92400000-0000-4000-8000-000000000001')" \
  >/dev/null
"${owner_psql[@]}" -f "$infra_dir/migrations/0024_career_reason_sharing.sql" >/dev/null
"${owner_psql[@]}" -f "$infra_dir/tests/paper-reset-fixtures.sql" >/dev/null

"${owner_psql[@]}" <<'SQL' >/dev/null
CREATE ROLE trimmy_reason_share_test_runtime
  LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
GRANT USAGE ON SCHEMA trimmy TO trimmy_reason_share_test_runtime;
GRANT EXECUTE ON FUNCTION trimmy.career_reason_privacy_get(uuid),
  trimmy.career_reason_privacy_put(uuid, uuid, text, bigint, text),
  trimmy.career_trade_reason_list(
    uuid, text, text, text, timestamptz, uuid, integer)
  TO trimmy_reason_share_test_runtime;
SQL

export TRIMMY_REASON_SHARING_TEST_SOCKET="$runtime_dir/socket"
export TRIMMY_REASON_SHARING_TEST_PORT=65452
cd "$project_dir"
npm run build:backend
node --import tsx --test \
  apps/api/test/integration/career-reason-sharing-postgres.test.ts

"${owner_psql[@]}" -c \
  'ALTER ROLE trimmy_reason_share_test_owner NOSUPERUSER NOBYPASSRLS' >/dev/null
"$postgres_bin/pg_ctl" -D "$runtime_dir/data" -m fast -w stop >/dev/null
started=0
"$postgres_bin/pg_ctl" -D "$runtime_dir/data" -l "$runtime_dir/postgres.log" \
  -o "-c listen_addresses='' -c unix_socket_directories='$runtime_dir/socket' -c port=65452" \
  -w start >/dev/null
started=1
TRIMMY_REASON_SHARING_TEST_RECOVERY=1 node --import tsx --test \
  apps/api/test/integration/career-reason-sharing-postgres.test.ts

echo 'PASS: Career reason privacy, feed visibility, pagination, cycle history, RLS and restart recovery.'
