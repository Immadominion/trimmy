#!/usr/bin/env bash
# Isolated migration-0023 reset, security, lock-race and restart harness.
set -euo pipefail

infra_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runtime_dir="$infra_dir/.paper-reset-runtime"
postgres_bin="${TRIMMY_POSTGRES_BIN:-}"
if [[ -z "$postgres_bin" ]]; then postgres_bin="$(pg_config --bindir)"; fi
for executable in initdb pg_ctl psql; do
  [[ -x "$postgres_bin/$executable" ]] || { echo "Missing binary: $executable" >&2; exit 1; }
done
[[ ${#runtime_dir} -le 80 ]] || { echo 'Checkout path is too long for private PostgreSQL sockets.' >&2; exit 1; }
(umask 077 && mkdir "$runtime_dir") \
  || { echo 'Paper-reset test runtime already exists; inspect before retrying.' >&2; exit 1; }
started=0
cleanup() {
  result=$?
  if [[ $started -eq 1 ]]; then
    "$postgres_bin/pg_ctl" -D "$runtime_dir/data" -m fast -w stop >/dev/null || true
  fi
  if [[ $result -ne 0 ]]; then
    [[ ! -f "$runtime_dir/postgres.log" ]] || tail -n 80 "$runtime_dir/postgres.log" >&2
  fi
  python3 - "$runtime_dir" <<'PY'
from pathlib import Path
import shutil
import sys
path = Path(sys.argv[1])
if path.name == '.paper-reset-runtime' and path.exists():
    shutil.rmtree(path)
PY
  exit "$result"
}
trap cleanup EXIT

mkdir "$runtime_dir/socket"
chmod 700 "$runtime_dir/socket"
"$postgres_bin/initdb" -D "$runtime_dir/data" -A trust --no-locale -E UTF8 \
  -U trimmy_reset_test_owner >"$runtime_dir/init.log"
"$postgres_bin/pg_ctl" -D "$runtime_dir/data" -l "$runtime_dir/postgres.log" \
  -o "-c listen_addresses='' -c unix_socket_directories='$runtime_dir/socket' -c port=65451" \
  -w start >/dev/null
started=1
owner_psql=("$postgres_bin/psql" -X -v ON_ERROR_STOP=1 -h "$runtime_dir/socket" \
  -p 65451 -U trimmy_reset_test_owner -d postgres)

for migration in "$infra_dir"/migrations/*.sql; do
  "${owner_psql[@]}" -f "$migration" >/dev/null
done
"${owner_psql[@]}" -f "$infra_dir/tests/paper-reset-fixtures.sql" >/dev/null

current_cycle_index="$("${owner_psql[@]}" -qAtc \
  "SELECT pg_get_indexdef('trimmy.paper_orders_current_cycle'::regclass)")"
[[ "$current_cycle_index" == \
  'CREATE INDEX paper_orders_current_cycle ON trimmy.paper_orders USING btree (user_id, account_revision DESC)' ]] \
  || { echo 'FAIL: current-cycle paper orders index is missing or changed.' >&2; exit 1; }

echo '--- reset semantics, replay, history, Career, reason, guest and security constraints'
"${owner_psql[@]}" -f "$infra_dir/tests/paper-reset-constraints.sql" \
  >"$runtime_dir/constraints.log"
tail -n 3 "$runtime_dir/constraints.log"

echo '--- reset-aware red-day reconstruction and immutable completed evidence'
"${owner_psql[@]}" -f "$infra_dir/tests/paper-reset-red-day.sql" \
  >"$runtime_dir/red-day.log"
tail -n 3 "$runtime_dir/red-day.log"

echo '--- FORCE RLS account policy and function-only serving role'
probe_psql=("$postgres_bin/psql" -X -qAt -v ON_ERROR_STOP=1 -h "$runtime_dir/socket" \
  -p 65451 -U trimmy_paper_reset_policy_probe -d postgres)
own_count="$("${probe_psql[@]}" -c \
  "SET trimmy.practice_user_id='92300000-0000-4000-8000-000000000001'; SELECT count(*) FROM trimmy.paper_reset_receipts WHERE user_id='92300000-0000-4000-8000-000000000001'")"
[[ "$own_count" -ge 1 ]] || { echo 'FAIL: account policy hid the authorized receipt.' >&2; exit 1; }
cross_count="$("${probe_psql[@]}" -c \
  "SET trimmy.practice_user_id='92300000-0000-4000-8000-000000000002'; SELECT count(*) FROM trimmy.paper_reset_receipts WHERE user_id='92300000-0000-4000-8000-000000000001'")"
[[ "$cross_count" == '0' ]] || { echo 'FAIL: account policy exposed a cross-account receipt.' >&2; exit 1; }
runtime_psql=("$postgres_bin/psql" -X -qAt -v ON_ERROR_STOP=1 -h "$runtime_dir/socket" \
  -p 65451 -U trimmy_paper_reset_test_runtime -d postgres)
if "${runtime_psql[@]}" -c 'SELECT count(*) FROM trimmy.paper_reset_receipts' \
    >/dev/null 2>&1; then
  echo 'FAIL: serving role read reset receipts directly.' >&2; exit 1
fi

echo '--- same-mutation concurrency, conflicting mutation, and reset-versus-commit serialization'
"${owner_psql[@]}" <<'SQL' >/dev/null
INSERT INTO trimmy.users(id) VALUES ('92320000-0000-4000-8000-000000000001');
SELECT public.paper_reset_test_buy(
  '92320000-0000-4000-8000-000000000001', 'concurrency',
  'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', clock_timestamp() + interval '1 second');
SQL
"${owner_psql[@]}" -qAt >"$runtime_dir/reset-a.out" <<'SQL' &
BEGIN;
SET LOCAL trimmy.practice_user_id='92320000-0000-4000-8000-000000000001';
SELECT outcome || '|' || previous_revision || '|' || revision
FROM trimmy.paper_desk_reset(
  '92320000-0000-4000-8000-000000000001',
  '92320000-0000-4000-8000-000000000300', repeat('1',64), 1);
SELECT pg_sleep(1);
COMMIT;
SQL
reset_a_pid=$!
sleep 0.15
"${owner_psql[@]}" -qAt >"$runtime_dir/reset-b.out" <<'SQL' &
BEGIN;
SET LOCAL trimmy.practice_user_id='92320000-0000-4000-8000-000000000001';
SELECT outcome || '|' || previous_revision || '|' || revision
FROM trimmy.paper_desk_reset(
  '92320000-0000-4000-8000-000000000001',
  '92320000-0000-4000-8000-000000000300', repeat('1',64), 1);
COMMIT;
SQL
reset_b_pid=$!
wait "$reset_a_pid"
wait "$reset_b_pid"
grep -q '^reset|1|2$' "$runtime_dir/reset-a.out" \
  || { echo 'FAIL: first concurrent reset did not succeed.' >&2; exit 1; }
grep -q '^reset|1|2$' "$runtime_dir/reset-b.out" \
  || { echo 'FAIL: same concurrent mutation did not replay.' >&2; exit 1; }
[[ "$("${owner_psql[@]}" -qAtc "SELECT count(*) FROM trimmy.paper_reset_receipts WHERE user_id='92320000-0000-4000-8000-000000000001' AND outcome='reset'")" == '1' ]] \
  || { echo 'FAIL: concurrent replay wrote more than one reset receipt.' >&2; exit 1; }
stale_out="$("${owner_psql[@]}" -qAtc \
  "BEGIN; SET LOCAL trimmy.practice_user_id='92320000-0000-4000-8000-000000000001'; SELECT outcome FROM trimmy.paper_desk_reset('92320000-0000-4000-8000-000000000001','92320000-0000-4000-8000-000000000301',repeat('2',64),1); COMMIT")"
grep -q '^stale_revision$' <<<"$stale_out" \
  || { echo 'FAIL: losing reset mutation was not stale.' >&2; exit 1; }

"${owner_psql[@]}" -qAt >"$runtime_dir/commit-a.out" <<'SQL' &
BEGIN;
SELECT public.paper_reset_test_buy(
  '92320000-0000-4000-8000-000000000001', 'commit-race',
  'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp',
  (SELECT updated_at + interval '1 second' FROM trimmy.paper_accounts
   WHERE user_id='92320000-0000-4000-8000-000000000001'));
SELECT pg_sleep(1);
COMMIT;
SQL
commit_a_pid=$!
sleep 0.15
"${owner_psql[@]}" -qAt >"$runtime_dir/reset-after-commit.out" <<'SQL' &
BEGIN;
SET LOCAL trimmy.practice_user_id='92320000-0000-4000-8000-000000000001';
SELECT outcome FROM trimmy.paper_desk_reset(
  '92320000-0000-4000-8000-000000000001',
  '92320000-0000-4000-8000-000000000302', repeat('3',64), 2);
COMMIT;
SQL
reset_after_commit_pid=$!
wait "$commit_a_pid"
wait "$reset_after_commit_pid"
grep -q '^stale_revision$' "$runtime_dir/reset-after-commit.out" \
  || { echo 'FAIL: reset did not serialize behind the winning paper commit.' >&2; exit 1; }

echo '--- reset works when its object owner has neither SUPERUSER nor BYPASSRLS'
"${owner_psql[@]}" <<'SQL' >/dev/null
INSERT INTO trimmy.users(id) VALUES ('92330000-0000-4000-8000-000000000001');
SELECT public.paper_reset_test_buy(
  '92330000-0000-4000-8000-000000000001', 'non-bypass',
  'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', clock_timestamp() + interval '1 second');
ALTER ROLE trimmy_reset_test_owner NOSUPERUSER NOBYPASSRLS;
SQL
non_bypass_first="$("${runtime_psql[@]}" -c \
  "BEGIN; SET LOCAL trimmy.practice_user_id='92330000-0000-4000-8000-000000000001'; SELECT outcome || '|' || previous_revision || '|' || revision FROM trimmy.paper_desk_reset('92330000-0000-4000-8000-000000000001','92330000-0000-4000-8000-000000000400',repeat('4',64),1); COMMIT")"
grep -q '^reset|1|2$' <<<"$non_bypass_first" \
  || { echo "FAIL: non-bypass function owner could not reset through RLS: $non_bypass_first" >&2; exit 1; }
authorized_owner_count="$("${owner_psql[@]}" -qAtc \
  "SET trimmy.practice_user_id='92330000-0000-4000-8000-000000000001'; SELECT count(*) FROM trimmy.paper_reset_receipts WHERE mutation_id='92330000-0000-4000-8000-000000000400'")"
[[ "$authorized_owner_count" == '1' ]] \
  || { echo 'FAIL: non-bypass table owner could not read its authorized receipt.' >&2; exit 1; }
cross_owner_count="$("${owner_psql[@]}" -qAtc \
  "SET trimmy.practice_user_id='92300000-0000-4000-8000-000000000002'; SELECT count(*) FROM trimmy.paper_reset_receipts WHERE mutation_id='92330000-0000-4000-8000-000000000400'")"
[[ "$cross_owner_count" == '0' ]] \
  || { echo 'FAIL: FORCE RLS exposed a receipt to the non-bypass table owner.' >&2; exit 1; }

echo '--- committed receipt replays exactly after PostgreSQL restart'
printf '%s\n' "$non_bypass_first" >"$runtime_dir/before-restart.out"
"$postgres_bin/pg_ctl" -D "$runtime_dir/data" -m fast -w stop >/dev/null
started=0
"$postgres_bin/pg_ctl" -D "$runtime_dir/data" -l "$runtime_dir/postgres.log" \
  -o "-c listen_addresses='' -c unix_socket_directories='$runtime_dir/socket' -c port=65451" \
  -w start >/dev/null
started=1
after_restart="$("${runtime_psql[@]}" -c \
  "BEGIN; SET LOCAL trimmy.practice_user_id='92330000-0000-4000-8000-000000000001'; SELECT outcome || '|' || previous_revision || '|' || revision FROM trimmy.paper_desk_reset('92330000-0000-4000-8000-000000000001','92330000-0000-4000-8000-000000000400',repeat('4',64),0); COMMIT")"
[[ "$after_restart" == "$non_bypass_first" ]] \
  || { echo 'FAIL: restart replay differed from the committed reset.' >&2; exit 1; }

echo 'PASS: paper reset SQL semantics, security, concurrency, Career/red-day invariants and restart recovery.'
