#!/usr/bin/env bash
set -euo pipefail
infra_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_dir="$(cd "$infra_dir/.." && pwd)"
runtime_dir="$infra_dir/.daily-desk-runtime"
postgres_bin="$(pg_config --bindir)"
(umask 077 && mkdir "$runtime_dir")
started=0
cleanup() {
  result=$?
  if [[ $started -eq 1 ]]; then "$postgres_bin/pg_ctl" -D "$runtime_dir/data" -m fast -w stop >/dev/null; fi
  if [[ $result -ne 0 ]]; then tail -30 "$runtime_dir/log"; fi
  rm -rf -- "$runtime_dir"
  exit "$result"
}
trap cleanup EXIT
mkdir "$runtime_dir/socket"
"$postgres_bin/initdb" -D "$runtime_dir/data" -A trust --no-locale -E UTF8 -U trimmy_daily_owner >/dev/null
"$postgres_bin/pg_ctl" -D "$runtime_dir/data" -l "$runtime_dir/log" -o "-c listen_addresses='' -c unix_socket_directories='$runtime_dir/socket' -p 65454" -w start >/dev/null
started=1
for migration in "$infra_dir"/migrations/*.sql; do
 "$postgres_bin/psql" -X -v ON_ERROR_STOP=1 -h "$runtime_dir/socket" -p 65454 -U trimmy_daily_owner -d postgres -f "$migration" >/dev/null
done
"$postgres_bin/psql" -X -v ON_ERROR_STOP=1 -h "$runtime_dir/socket" -p 65454 -U trimmy_daily_owner -d postgres -f "$infra_dir/tests/paper-reset-fixtures.sql" >/dev/null
cd "$project_dir"
TRIMMY_DAILY_DESK_TEST_SOCKET="$runtime_dir/socket" node --import tsx --test apps/api/test/integration/daily-desk-postgres.test.ts
