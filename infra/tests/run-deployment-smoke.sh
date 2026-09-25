#!/usr/bin/env bash
# The full deployment rehearsal: provision a TLS-only PostgreSQL the way a
# managed provider does, apply migrations with the deployment runner using OWNER
# credentials, then run the real built API against the RESTRICTED runtime role
# and exercise the authenticated practice path over HTTP.
#
# This is the end-to-end answer to "does the system actually run", short of
# pointing it at a hosted database and a real identity provider.
set -euo pipefail

infra_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_dir="$(cd "$infra_dir/.." && pwd)"
runtime_dir="$infra_dir/.deployment-runtime"
port=65440
api_port=4455
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
command -v openssl >/dev/null 2>&1 || { echo 'openssl is required.' >&2; exit 1; }
[[ ${#runtime_dir} -le 80 ]] || { echo 'Checkout path is too long for private PostgreSQL sockets.' >&2; exit 1; }
(umask 077 && mkdir "$runtime_dir") || { echo 'Deployment test runtime already exists; inspect before retrying.' >&2; exit 1; }

started=0
cleanup() {
  result=$?
  if [[ $started -eq 1 ]]; then
    "$postgres_bin/pg_ctl" -D "$runtime_dir/data" -m fast -w stop >/dev/null || true
  fi
  if [[ $result -ne 0 && -f "$runtime_dir/postgres.log" ]]; then
    tail -n 25 "$runtime_dir/postgres.log" >&2
  fi
  rm -rf -- "$runtime_dir"
  exit "$result"
}
trap cleanup EXIT

owner_role=trimmy_deploy_owner
runtime_role=trimmy_practice_runtime
red_day_capability_role=trimmy_red_day_verifier
red_day_worker_role=trimmy_red_day_worker
social_moderator_role=trimmy_social_moderator
owner_password="$(openssl rand -hex 24)"
runtime_password="$(openssl rand -hex 24)"
red_day_worker_password="$(openssl rand -hex 24)"

mkdir "$runtime_dir/socket" "$runtime_dir/tls"
chmod 700 "$runtime_dir/socket" "$runtime_dir/tls"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$runtime_dir/tls/ca.key" \
  -out "$runtime_dir/tls/ca.crt" -days 1 -subj "/CN=trimmy-deployment-test-ca" >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -keyout "$runtime_dir/tls/server.key" \
  -out "$runtime_dir/tls/server.csr" -subj "/CN=localhost" >/dev/null 2>&1
printf 'subjectAltName=DNS:localhost,IP:127.0.0.1\nbasicConstraints=critical,CA:FALSE\nextendedKeyUsage=serverAuth\n' \
  >"$runtime_dir/tls/server.ext"
openssl x509 -req -in "$runtime_dir/tls/server.csr" -CA "$runtime_dir/tls/ca.crt" \
  -CAkey "$runtime_dir/tls/ca.key" -CAcreateserial -out "$runtime_dir/tls/server.crt" \
  -days 1 -extfile "$runtime_dir/tls/server.ext" >/dev/null 2>&1
chmod 600 "$runtime_dir/tls/server.key" "$runtime_dir/tls/ca.key"

printf '%s\n' "$owner_password" > "$runtime_dir/init.pw"
chmod 600 "$runtime_dir/init.pw"
"$postgres_bin/initdb" -D "$runtime_dir/data" -A scram-sha-256 \
  --pwfile="$runtime_dir/init.pw" -U "$owner_role" --no-locale -E UTF8 >"$runtime_dir/init.log"
rm -f "$runtime_dir/init.pw"

cat >>"$runtime_dir/data/postgresql.conf" <<CONF
listen_addresses = 'localhost'
port = $port
unix_socket_directories = '$runtime_dir/socket'
ssl = on
ssl_cert_file = '$runtime_dir/tls/server.crt'
ssl_key_file = '$runtime_dir/tls/server.key'
CONF
cat >"$runtime_dir/data/pg_hba.conf" <<HBA
local     all  $owner_role                 scram-sha-256
hostssl   all  all          127.0.0.1/32   scram-sha-256
hostssl   all  all          ::1/128        scram-sha-256
hostnossl all  all          127.0.0.1/32   reject
hostnossl all  all          ::1/128        reject
host      all  all          0.0.0.0/0      reject
host      all  all          ::/0           reject
HBA

"$postgres_bin/pg_ctl" -D "$runtime_dir/data" -l "$runtime_dir/postgres.log" -w start >/dev/null
started=1

owner_psql() {
  PGPASSWORD="$owner_password" "$postgres_bin/psql" -X -v ON_ERROR_STOP=1 \
    -h "$runtime_dir/socket" -p "$port" -U "$owner_role" "$@"
}
owner_psql -d postgres -c "CREATE DATABASE trimmy" >/dev/null
printf "\\set runtime_pw '%s'\n\\set worker_pw '%s'\nCREATE ROLE %s LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS PASSWORD :'runtime_pw';\nCREATE ROLE %s NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;\nCREATE ROLE %s LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS PASSWORD :'worker_pw';\nCREATE ROLE %s NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;\nGRANT %s TO %s;\n" \
  "$runtime_password" "$red_day_worker_password" "$runtime_role" \
  "$red_day_capability_role" "$red_day_worker_role" \
  "$social_moderator_role" \
  "$red_day_capability_role" "$red_day_worker_role" | owner_psql -d trimmy -f - >/dev/null

cd "$project_dir"
echo '--- build the backend exactly as the image does'
npm run build:backend >/dev/null

echo '--- apply migrations with owner credentials'
migration_output="$(
  TRIMMY_MIGRATION_DATABASE_URL="postgresql://$owner_role:$owner_password@localhost:$port/trimmy" \
  TRIMMY_MIGRATION_DATABASE_CA_FILE="$runtime_dir/tls/ca.crt" \
  TRIMMY_MIGRATION_RUNTIME_ROLE="$runtime_role" \
  TRIMMY_MIGRATION_RED_DAY_CAPABILITY_ROLE="$red_day_capability_role" \
  TRIMMY_MIGRATION_RED_DAY_WORKER_ROLE="$red_day_worker_role" \
  TRIMMY_MIGRATION_SOCIAL_MODERATOR_ROLE="$social_moderator_role" \
  TRIMMY_MIGRATION_RELATIONSHIP_CUTOVER=drained-v2 \
  TRIMMY_MIGRATION_ACTIVATE_RED_DAY=false \
    node tool/runtime/apply-migrations.mjs
)"
echo "$migration_output"
grep -q 'Applied 32 migration(s)' <<<"$migration_output" \
  || { echo 'FAIL: deployment smoke did not apply the current 32 migrations.' >&2; exit 1; }
[[ "$(owner_psql -d trimmy -Atc "SELECT count(*)=32 AND max(version)='0032_live_stock_order_history' FROM trimmy.schema_migrations")" == 't' ]] \
  || { echo 'FAIL: deployment smoke did not record the current 32-migration history.' >&2; exit 1; }
[[ "$(owner_psql -d trimmy -Atc "SELECT count(*)=4 FROM pg_roles WHERE rolname=ANY(ARRAY['$runtime_role','$red_day_capability_role','$red_day_worker_role','$social_moderator_role'])")" == 't' ]] \
  || { echo 'FAIL: deployment smoke did not provision all four isolated roles.' >&2; exit 1; }
[[ "$(owner_psql -d trimmy -Atc "SELECT NOT rolcanlogin AND NOT rolinherit AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication AND NOT rolbypassrls FROM pg_roles WHERE rolname='$social_moderator_role'")" == 't' ]] \
  || { echo 'FAIL: the social moderator is not a safe NOLOGIN NOINHERIT role.' >&2; exit 1; }
[[ "$(owner_psql -d trimmy -Atc "SELECT has_schema_privilege('$social_moderator_role','trimmy','USAGE') AND NOT has_schema_privilege('$social_moderator_role','trimmy','CREATE') AND has_function_privilege('$social_moderator_role','trimmy.social_reason_moderation_put(uuid,bigint,text,text,text)','EXECUTE') AND NOT has_function_privilege('$runtime_role','trimmy.social_reason_moderation_put(uuid,bigint,text,text,text)','EXECUTE') AND NOT pg_has_role('$runtime_role','$social_moderator_role','MEMBER')")" == 't' ]] \
  || { echo 'FAIL: moderation authority is not isolated from the API runtime.' >&2; exit 1; }
[[ "$(owner_psql -d trimmy -Atc "SELECT count(*)=1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='trimmy' AND has_function_privilege('$social_moderator_role',p.oid,'EXECUTE')")" == 't' ]] \
  || { echo 'FAIL: the social moderator can execute more than its one reviewed function.' >&2; exit 1; }
[[ "$(owner_psql -d trimmy -Atc "SELECT evidence_live FROM trimmy.career_mission_definitions WHERE id='hold-through-red-day'")" == 'f' ]] \
  || { echo 'FAIL: deployment smoke activated red-day evidence without the explicit terms gate.' >&2; exit 1; }

echo '--- optional introduction preserves honest skips and confirmed-buy evidence'
owner_psql -d trimmy -f "$infra_dir/tests/optional-introduction-constraints.sql"

echo '--- serve the real API with the restricted runtime role'
TRIMMY_SMOKE_DATABASE_URL="postgresql://$runtime_role:$runtime_password@localhost:$port/trimmy" \
TRIMMY_SMOKE_DATABASE_CA_FILE="$runtime_dir/tls/ca.crt" \
TRIMMY_SMOKE_SOCIAL_MODERATOR_ROLE="$social_moderator_role" \
TRIMMY_SMOKE_PORT="$api_port" \
  node tool/testing/deployment-smoke.mjs

echo '--- the serving role still cannot migrate or read financial tables'
export PGPASSWORD="$runtime_password"
runtime_conn="host=localhost port=$port dbname=trimmy user=$runtime_role sslmode=verify-full sslrootcert=$runtime_dir/tls/ca.crt"
if "$postgres_bin/psql" -X -Atc 'CREATE TABLE trimmy.should_not_exist(id int)' "$runtime_conn" >/dev/null 2>&1; then
  echo 'FAIL: the serving role was able to run DDL.' >&2; exit 1
fi
if "$postgres_bin/psql" -X -Atc 'SELECT count(*) FROM trimmy.financial_intents' "$runtime_conn" >/dev/null 2>&1; then
  echo 'FAIL: the serving role reached a financial table.' >&2; exit 1
fi
if "$postgres_bin/psql" -X -Atc 'SELECT count(*) FROM trimmy.product_launch_action_receipts' "$runtime_conn" >/dev/null 2>&1; then
  echo 'FAIL: the serving role reached product launch receipts directly.' >&2; exit 1
fi
if "$postgres_bin/psql" -X -Atc 'SELECT * FROM trimmy.career_red_day_candidates(1)' "$runtime_conn" >/dev/null 2>&1; then
  echo 'FAIL: the serving API role reached red-day worker authority.' >&2; exit 1
fi
if "$postgres_bin/psql" -X -Atc 'SELECT trimmy.career_red_day_activate()' "$runtime_conn" >/dev/null 2>&1; then
  echo 'FAIL: the serving API role reached red-day activation authority.' >&2; exit 1
fi
unset PGPASSWORD

echo 'PASS: migrations applied with owner credentials, the built API served the restricted role over HTTP, and the serving role kept its boundary; private cluster will be removed.'
