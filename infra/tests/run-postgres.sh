#!/usr/bin/env bash
set -euo pipefail

infra_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runtime_dir="$infra_dir/.test-runtime"
postgres_bin="${TRIMMY_POSTGRES_BIN:-}"
if [[ -z "$postgres_bin" ]]; then
  if command -v pg_config >/dev/null 2>&1; then
    postgres_bin="$(pg_config --bindir)"
  elif command -v pg_ctl >/dev/null 2>&1; then
    postgres_bin="$(dirname "$(command -v pg_ctl)")"
  else
    echo 'PostgreSQL binaries unavailable. Set TRIMMY_POSTGRES_BIN to an installed bin directory.' >&2
    exit 1
  fi
fi
for executable in initdb pg_ctl psql; do
  [[ -x "$postgres_bin/$executable" ]] || { echo "Missing PostgreSQL binary: $executable" >&2; exit 1; }
done
if [[ ${#runtime_dir} -gt 80 ]]; then
  echo 'Workspace path is too long for private PostgreSQL Unix sockets; use a shorter checkout path.' >&2
  exit 1
fi
# mkdir is our concurrency guard. Never attach to an existing server or runtime.
(umask 077 && mkdir "$runtime_dir") || { echo 'A test runtime already exists; inspect it before retrying.' >&2; exit 1; }
started=0
cleanup() {
  result=$?
  if [[ $started -eq 1 ]]; then
    "$postgres_bin/pg_ctl" -D "$runtime_dir/data" -m fast -w stop >/dev/null || true
  fi
  if [[ $result -ne 0 ]]; then
    [[ ! -f "$runtime_dir/test.log" ]] || cat "$runtime_dir/test.log" >&2
    [[ ! -f "$runtime_dir/postgres.log" ]] || tail -n 30 "$runtime_dir/postgres.log" >&2
  fi
  # This exact directory was created by this run; no caller-supplied deletion path.
  rm -rf -- "$runtime_dir"
  exit "$result"
}
trap cleanup EXIT
mkdir "$runtime_dir/socket"
chmod 700 "$runtime_dir/socket"
"$postgres_bin/initdb" -D "$runtime_dir/data" -A trust --no-locale -E UTF8 -U trimmy_test_owner >"$runtime_dir/init.log"
"$postgres_bin/pg_ctl" -D "$runtime_dir/data" -l "$runtime_dir/postgres.log" \
  -o "-c listen_addresses='' -c unix_socket_directories='$runtime_dir/socket' -c port=65439" -w start >/dev/null
started=1
psql_args=(-X -v ON_ERROR_STOP=1 -h "$runtime_dir/socket" -p 65439 -U trimmy_test_owner -d postgres)
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/migrations/0001_foundation.sql" >"$runtime_dir/migration.log"
"$postgres_bin/psql" "${psql_args[@]}" -f "$infra_dir/tests/constraints.sql" >"$runtime_dir/test.log"
checks="$("$postgres_bin/psql" "${psql_args[@]}" -Atc "SELECT count(*) FROM trimmy.assets")"
[[ "$checks" = '0' ]] || { echo 'Test rollback left asset fixture data behind.' >&2; exit 1; }
"$postgres_bin/psql" "${psql_args[@]}" -Atc "SELECT version()"
tail -n 6 "$runtime_dir/test.log"
echo 'PASS: baseline migration, constraints, transaction rollback, privileges and RLS; private cluster will be removed.'
