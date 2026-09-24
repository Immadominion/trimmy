#!/usr/bin/env bash
# Isolated migration-0021 evidence and worker-role harness.
set -euo pipefail

infra_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_dir="$(cd "$infra_dir/.." && pwd)"
runtime_dir="$infra_dir/.red-day-runtime"
postgres_bin="${TRIMMY_POSTGRES_BIN:-}"
if [[ -z "$postgres_bin" ]]; then postgres_bin="$(pg_config --bindir)"; fi
for executable in initdb pg_ctl psql; do
  [[ -x "$postgres_bin/$executable" ]] || { echo "Missing binary: $executable" >&2; exit 1; }
done
[[ ${#runtime_dir} -le 80 ]] || { echo 'Checkout path is too long for private PostgreSQL sockets.' >&2; exit 1; }
(umask 077 && mkdir "$runtime_dir") || { echo 'Red-day test runtime already exists; inspect before retrying.' >&2; exit 1; }
started=0
cleanup() {
  result=$?
  if [[ $started -eq 1 ]]; then
    "$postgres_bin/pg_ctl" -D "$runtime_dir/data" -m fast -w stop >/dev/null || true
  fi
  if [[ $result -ne 0 ]]; then
    [[ ! -f "$runtime_dir/postgres.log" ]] || tail -n 30 "$runtime_dir/postgres.log" >&2
  fi
  python3 - "$runtime_dir" <<'PY'
from pathlib import Path
import shutil
import sys
path = Path(sys.argv[1])
if path.name == '.red-day-runtime' and path.exists():
    shutil.rmtree(path)
PY
  exit "$result"
}
trap cleanup EXIT

mkdir "$runtime_dir/socket"
chmod 700 "$runtime_dir/socket"
"$postgres_bin/initdb" -D "$runtime_dir/data" -A trust --no-locale -E UTF8 \
  -U trimmy_red_day_test_owner >"$runtime_dir/init.log"
"$postgres_bin/pg_ctl" -D "$runtime_dir/data" -l "$runtime_dir/postgres.log" \
  -o "-c listen_addresses='' -c unix_socket_directories='$runtime_dir/socket' -c port=65447" -w start >/dev/null
started=1
psql_args=(-X -v ON_ERROR_STOP=1 -h "$runtime_dir/socket" -p 65447 \
  -U trimmy_red_day_test_owner -d postgres)

for migration in "$infra_dir"/migrations/000{1..9}_*.sql "$infra_dir"/migrations/001{0..7}_*.sql; do
  "$postgres_bin/psql" "${psql_args[@]}" -f "$migration" >/dev/null
done
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/tests/career-red-day-fixtures.sql" >/dev/null
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/0018_career_missions_and_promotions.sql" >/dev/null
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/0019_career_local_day.sql" >/dev/null
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/0020_guest_creation_abuse_and_retention.sql" >/dev/null
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/0021_career_red_day_evidence.sql" >/dev/null

"$postgres_bin/psql" "${psql_args[@]}" <<'SQL' >/dev/null
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM trimmy.career_mission_definitions
    WHERE id='hold-through-red-day' AND evidence_live) THEN
    RAISE EXCEPTION 'Migration activated red-day evidence before worker grants';
  END IF;
  IF EXISTS (SELECT 1 FROM trimmy.career_red_day_candidates(100)) THEN
    RAISE EXCEPTION 'Locked red-day evidence still exposed provider candidates';
  END IF;
END $$;
CREATE ROLE trimmy_red_day_test_verifier NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
CREATE ROLE trimmy_red_day_test_worker LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
CREATE ROLE trimmy_red_day_test_api LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
GRANT trimmy_red_day_test_verifier TO trimmy_red_day_test_worker;
GRANT USAGE ON SCHEMA trimmy TO trimmy_red_day_test_verifier, trimmy_red_day_test_api;
GRANT EXECUTE ON FUNCTION trimmy.career_red_day_candidates(integer),
  trimmy.career_red_day_pending_sessions(integer),
  trimmy.career_red_day_process_session(uuid, integer),
  trimmy.career_red_day_record_observation(
    uuid, text, text, text, text, text, date, date, text, text,
    timestamptz, timestamptz, text, text, uuid, uuid, text, text, text,
    text, text, text, timestamptz)
  TO trimmy_red_day_test_verifier;
SELECT trimmy.career_red_day_activate();
SQL

export TRIMMY_RED_DAY_TEST_SOCKET="$runtime_dir/socket"
export TRIMMY_RED_DAY_TEST_PORT=65447
cd "$project_dir"
npm run build:backend
node --import tsx --test apps/api/test/integration/career-red-day-postgres.test.ts

"$postgres_bin/pg_ctl" -D "$runtime_dir/data" -m fast -w stop >/dev/null
started=0
"$postgres_bin/pg_ctl" -D "$runtime_dir/data" -l "$runtime_dir/postgres.log" \
  -o "-c listen_addresses='' -c unix_socket_directories='$runtime_dir/socket' -c port=65447" -w start >/dev/null
started=1
TRIMMY_RED_DAY_TEST_RECOVERY=1 node --import tsx --test \
  apps/api/test/integration/career-red-day-postgres.test.ts
echo 'PASS: red-day provider evidence, holding reconstruction, privileges, idempotency and restart recovery.'
