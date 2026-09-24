#!/usr/bin/env bash
# Proves tool/runtime/apply-migrations.mjs against a real PostgreSQL that
# requires TLS, exactly as a managed provider does. It verifies that every
# migration applies to an empty database over a verified connection, that a
# second run is idempotent, that plaintext is refused, that the restricted
# runtime role receives working privileges without gaining DDL, and that a
# database ahead of this build is refused instead of downgraded.
set -euo pipefail

infra_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_dir="$(cd "$infra_dir/.." && pwd)"
runtime_dir="$infra_dir/.migration-runtime"
port=65439
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
(umask 077 && mkdir "$runtime_dir") || { echo 'Migration test runtime already exists; inspect before retrying.' >&2; exit 1; }

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

owner_role=trimmy_migration_owner
runtime_role=trimmy_practice_runtime
red_day_capability_role=trimmy_red_day_verifier
red_day_worker_role=trimmy_red_day_worker
social_moderator_role=trimmy_social_moderator
ordinary_owner_role=trimmy_plain_migration_owner
owner_password="$(openssl rand -hex 24)"
runtime_password="$(openssl rand -hex 24)"
red_day_worker_password="$(openssl rand -hex 24)"
ordinary_owner_password="$(openssl rand -hex 24)"

mkdir "$runtime_dir/socket" "$runtime_dir/tls"
chmod 700 "$runtime_dir/socket" "$runtime_dir/tls"
# A private CA signs the server certificate, and only the CA is pinned. This is
# the shape a managed provider hands you. The IP SAN lets the client verify the
# host it actually dialled rather than skipping the check.
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$runtime_dir/tls/ca.key" \
  -out "$runtime_dir/tls/ca.crt" -days 1 -subj "/CN=trimmy-migration-test-ca" >/dev/null 2>&1
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
# Plaintext TCP is rejected outright, so the runner cannot silently migrate
# over an unencrypted connection.
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

# The owner authenticates over the private socket; its password never appears
# in argv or a log line.
owner_psql() {
  PGPASSWORD="$owner_password" "$postgres_bin/psql" -X -v ON_ERROR_STOP=1 \
    -h "$runtime_dir/socket" -p "$port" -U "$owner_role" "$@"
}
owner_psql -d postgres -c "CREATE DATABASE trimmy" >/dev/null
printf "\\set runtime_pw '%s'\n\\set worker_pw '%s'\n\\set ordinary_pw '%s'\nCREATE ROLE %s LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS PASSWORD :'runtime_pw';\nCREATE ROLE %s NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;\nCREATE ROLE %s LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS PASSWORD :'worker_pw';\nCREATE ROLE %s NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;\nCREATE ROLE %s LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS PASSWORD :'ordinary_pw';\nGRANT %s TO %s;\n" \
  "$runtime_password" "$red_day_worker_password" "$ordinary_owner_password" "$runtime_role" \
  "$red_day_capability_role" "$red_day_worker_role" \
  "$social_moderator_role" "$ordinary_owner_role" \
  "$red_day_capability_role" "$red_day_worker_role" | owner_psql -d trimmy -f - >/dev/null

export TRIMMY_MIGRATION_DATABASE_CA_FILE="$runtime_dir/tls/ca.crt"
export TRIMMY_MIGRATION_RUNTIME_ROLE="$runtime_role"
export TRIMMY_MIGRATION_RED_DAY_CAPABILITY_ROLE="$red_day_capability_role"
export TRIMMY_MIGRATION_RED_DAY_WORKER_ROLE="$red_day_worker_role"
export TRIMMY_MIGRATION_SOCIAL_MODERATOR_ROLE="$social_moderator_role"
export TRIMMY_MIGRATION_RELATIONSHIP_CUTOVER=drained-v2
export TRIMMY_MIGRATION_ACTIVATE_RED_DAY=false
cd "$project_dir"

echo '--- a plain database owner is rejected before FORCE RLS migrations'
export TRIMMY_MIGRATION_DATABASE_URL="postgresql://$ordinary_owner_role:$ordinary_owner_password@localhost:$port/trimmy"
if authority_error="$(node tool/runtime/apply-migrations.mjs 2>&1)"; then
  echo 'FAIL: a migration role without SUPERUSER or BYPASSRLS was accepted.' >&2; exit 1
fi
grep -q 'must be SUPERUSER or BYPASSRLS' <<<"$authority_error" \
  || { echo "FAIL: unexpected migration-authority refusal: $authority_error" >&2; exit 1; }
[[ "$(owner_psql -d trimmy -Atc "SELECT to_regclass('trimmy.schema_migrations') IS NULL")" == 't' ]] \
  || { echo 'FAIL: plain migration role changed schema before refusal.' >&2; exit 1; }
export TRIMMY_MIGRATION_DATABASE_URL="postgresql://$owner_role:$owner_password@localhost:$port/trimmy"

echo '--- relationship authority cutover requires an explicit drain boundary'
cutover_database=trimmy_relationship_cutover
owner_psql -d postgres -c "CREATE DATABASE $cutover_database" >/dev/null
for migration in "$infra_dir"/migrations/*.sql; do
  [[ "$(basename "$migration")" == '0025_relationship_safety.sql' ]] && break
  owner_psql -d "$cutover_database" -f "$migration" >/dev/null
done
export TRIMMY_MIGRATION_DATABASE_URL="postgresql://$owner_role:$owner_password@localhost:$port/$cutover_database"
unset TRIMMY_MIGRATION_RELATIONSHIP_CUTOVER
if cutover_error="$(node tool/runtime/apply-migrations.mjs 2>&1)"; then
  echo 'FAIL: relationship migration accepted an unacknowledged API cutover.' >&2; exit 1
fi
grep -q 'acknowledged drained-v2 API cutover' <<<"$cutover_error" \
  || { echo "FAIL: unexpected cutover refusal: $cutover_error" >&2; exit 1; }
export TRIMMY_MIGRATION_RELATIONSHIP_CUTOVER=drained-v2
owner_tls_conn="host=localhost port=$port dbname=$cutover_database user=$owner_role sslmode=verify-full sslrootcert=$runtime_dir/tls/ca.crt"
PGAPPNAME=trimmy-practice-api PGPASSWORD="$owner_password" \
  "$postgres_bin/psql" -X -Atc 'SELECT pg_sleep(30)' "$owner_tls_conn" >/dev/null &
api_session_pid=$!
for _ in 1 2 3 4 5; do
  [[ "$(owner_psql -d "$cutover_database" -Atc "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND application_name='trimmy-practice-api'")" == '1' ]] && break
  sleep 0.1
done
[[ "$(owner_psql -d "$cutover_database" -Atc "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND application_name='trimmy-practice-api'")" == '1' ]] \
  || { echo 'FAIL: could not establish the cutover API-session fixture.' >&2; exit 1; }
if cutover_error="$(node tool/runtime/apply-migrations.mjs 2>&1)"; then
  echo 'FAIL: relationship migration accepted a connected API pool.' >&2; exit 1
fi
grep -q 'trimmy-practice-api database session to be drained' <<<"$cutover_error" \
  || { echo "FAIL: unexpected active-session refusal: $cutover_error" >&2; exit 1; }
owner_psql -d "$cutover_database" -c \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname=current_database() AND application_name='trimmy-practice-api'" >/dev/null
wait "$api_session_pid" 2>/dev/null || true
owner_psql -d postgres -c "DROP DATABASE $cutover_database" >/dev/null
export TRIMMY_MIGRATION_DATABASE_URL="postgresql://$owner_role:$owner_password@localhost:$port/trimmy"

echo '--- first run applies every migration over verified TLS'
first="$(node tool/runtime/apply-migrations.mjs)"
echo "$first"
grep -q 'Applied 31 migration(s)' <<<"$first" || { echo 'FAIL: expected 31 migrations applied.' >&2; exit 1; }
grep -q 'Red-day evidence is locked' <<<"$first" || { echo 'FAIL: red-day evidence activated without the explicit gate.' >&2; exit 1; }

recorded="$(owner_psql -d trimmy -Atc "SELECT string_agg(version, ',' ORDER BY version) FROM trimmy.schema_migrations")"
expected='0001_foundation,0002_practice_progress,0003_practice_accounts,0004_watchlists,0005_practice_payload_v4,0006_practice_payload_v5,0007_wallet_possession_and_reviews,0008_practice_payload_v6,0009_invitations,0010_account_closure,0011_wallet_possession_challenges,0012_followed_stocks,0013_paper_trading,0014_guest_sessions,0015_product_profiles,0016_guest_creation_idempotency,0017_career_core,0018_career_missions_and_promotions,0019_career_local_day,0020_guest_creation_abuse_and_retention,0021_career_red_day_evidence,0022_product_launch_evidence,0023_paper_reset,0024_career_reason_sharing,0025_relationship_safety,0026_optional_introduction,0027_career_activity_week,0028_community_following,0029_daily_desk,0030_intern_workdays,0031_live_stock_orders'
[[ "$recorded" == "$expected" ]] || { echo "FAIL: recorded migrations mismatch: $recorded" >&2; exit 1; }
[[ "$(owner_psql -d trimmy -Atc "SELECT NOT rolcanlogin AND NOT rolinherit AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication AND NOT rolbypassrls FROM pg_roles WHERE rolname='$social_moderator_role'")" == 't' ]] \
  || { echo 'FAIL: social moderator role is not safe NOLOGIN NOINHERIT.' >&2; exit 1; }
[[ "$(owner_psql -d trimmy -Atc "SELECT has_schema_privilege('$social_moderator_role','trimmy','USAGE') AND NOT has_schema_privilege('$social_moderator_role','trimmy','CREATE') AND has_function_privilege('$social_moderator_role','trimmy.social_reason_moderation_put(uuid,bigint,text,text,text)','EXECUTE') AND NOT has_function_privilege('$runtime_role','trimmy.social_reason_moderation_put(uuid,bigint,text,text,text)','EXECUTE') AND NOT pg_has_role('$runtime_role','$social_moderator_role','MEMBER')")" == 't' ]] \
  || { echo 'FAIL: moderation authority is not isolated from the API runtime.' >&2; exit 1; }
[[ "$(owner_psql -d trimmy -Atc "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='trimmy' AND has_function_privilege('$social_moderator_role',p.oid,'EXECUTE')")" == '1' ]] \
  || { echo 'FAIL: moderator role can execute more than one Trimmy function.' >&2; exit 1; }

echo '--- relationship migration preflight rejects ambiguous and malformed X identity history'
preflight_database=trimmy_relationship_preflight
owner_psql -d postgres -c "CREATE DATABASE $preflight_database" >/dev/null
for migration in "$infra_dir"/migrations/*.sql; do
  [[ "$(basename "$migration")" == '0025_relationship_safety.sql' ]] && break
  owner_psql -d "$preflight_database" -f "$migration" >/dev/null
done
owner_psql -d "$preflight_database" -c \
  "INSERT INTO trimmy.users(id) VALUES ('26000000-0000-4000-8000-000000000001'); INSERT INTO trimmy.provider_identities(user_id,provider,subject,handle_snapshot,verified_at) VALUES ('26000000-0000-4000-8000-000000000001','x','1','first',clock_timestamp()), ('26000000-0000-4000-8000-000000000001','x','2','second',clock_timestamp())" >/dev/null
if preflight_error="$(owner_psql -d "$preflight_database" \
    -f "$infra_dir/migrations/0025_relationship_safety.sql" 2>&1)"; then
  echo 'FAIL: relationship migration accepted duplicate provider/user identity history.' >&2; exit 1
fi
grep -q 'duplicate provider/user bindings' <<<"$preflight_error" \
  || { echo "FAIL: unexpected provider/user preflight error: $preflight_error" >&2; exit 1; }
owner_psql -d "$preflight_database" -c \
  "ALTER TABLE trimmy.provider_identities DISABLE TRIGGER USER; DELETE FROM trimmy.provider_identities WHERE subject = '2'; UPDATE trimmy.provider_identities SET subject = '0' WHERE subject = '1'; ALTER TABLE trimmy.provider_identities ENABLE TRIGGER USER" >/dev/null
if preflight_error="$(owner_psql -d "$preflight_database" \
    -f "$infra_dir/migrations/0025_relationship_safety.sql" 2>&1)"; then
  echo 'FAIL: relationship migration accepted a malformed historical X subject.' >&2; exit 1
fi
grep -q 'invalid X binding' <<<"$preflight_error" \
  || { echo "FAIL: unexpected X-subject preflight error: $preflight_error" >&2; exit 1; }
owner_psql -d "$preflight_database" -c \
  "ALTER TABLE trimmy.provider_identities DISABLE TRIGGER USER; UPDATE trimmy.provider_identities SET subject = '1' WHERE subject = '0'; ALTER TABLE trimmy.provider_identities ENABLE TRIGGER USER; ALTER TABLE trimmy.invitations DISABLE TRIGGER USER; INSERT INTO trimmy.invitations(sender_user_id,recipient_provider,recipient_subject,recipient_handle_snapshot,state,expires_at,version) VALUES ('26000000-0000-4000-8000-000000000001','x','1','Bad_Handle','addressed',clock_timestamp()+interval '1 day',9007199254740991); ALTER TABLE trimmy.invitations ENABLE TRIGGER USER" >/dev/null
if preflight_error="$(owner_psql -d "$preflight_database" \
    -f "$infra_dir/migrations/0025_relationship_safety.sql" 2>&1)"; then
  echo 'FAIL: relationship migration accepted malformed invitation history.' >&2; exit 1
fi
grep -q 'invalid invitation history row' <<<"$preflight_error" \
  || { echo "FAIL: unexpected invitation preflight error: $preflight_error" >&2; exit 1; }
[[ "$(owner_psql -d "$preflight_database" -Atc "SELECT to_regclass('trimmy.social_profiles') IS NULL")" == 't' ]] \
  || { echo 'FAIL: failed relationship preflight left partial schema changes.' >&2; exit 1; }
owner_psql -d postgres -c "DROP DATABASE $preflight_database" >/dev/null

[[ "$(owner_psql -d trimmy -Atc "SELECT evidence_live FROM trimmy.career_mission_definitions WHERE id='hold-through-red-day'")" == 'f' ]] \
  || { echo 'FAIL: red-day evidence must remain locked after schema/grants deployment.' >&2; exit 1; }

echo '--- deployment rejects direct and transitive extra capability ingress'
rogue_role=trimmy_red_day_rogue
bridge_role=trimmy_red_day_bridge
owner_psql -d trimmy -c \
  "CREATE ROLE $rogue_role LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS; GRANT $red_day_capability_role TO $rogue_role" >/dev/null
if ingress_error="$(node tool/runtime/apply-migrations.mjs --grants-only 2>&1)"; then
  echo 'FAIL: deploy accepted a second direct capability member.' >&2; exit 1
fi
grep -q 'Only the dedicated red-day worker may reach the capability role' <<<"$ingress_error" \
  || { echo "FAIL: unexpected direct-ingress refusal: $ingress_error" >&2; exit 1; }
owner_psql -d trimmy -c \
  "REVOKE $red_day_capability_role FROM $rogue_role; CREATE ROLE $bridge_role NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS; GRANT $red_day_capability_role TO $bridge_role; GRANT $bridge_role TO $rogue_role" >/dev/null
if ingress_error="$(node tool/runtime/apply-migrations.mjs --grants-only 2>&1)"; then
  echo 'FAIL: deploy accepted an indirect capability member chain.' >&2; exit 1
fi
grep -q 'Only the dedicated red-day worker may reach the capability role' <<<"$ingress_error" \
  || { echo "FAIL: unexpected indirect-ingress refusal: $ingress_error" >&2; exit 1; }
owner_psql -d trimmy -c \
  "REVOKE $bridge_role FROM $rogue_role; REVOKE $red_day_capability_role FROM $bridge_role; DROP ROLE $bridge_role; DROP ROLE $rogue_role" >/dev/null
owner_psql -d trimmy -c \
  "GRANT $red_day_capability_role TO $red_day_worker_role WITH ADMIN OPTION" >/dev/null
if membership_error="$(node tool/runtime/apply-migrations.mjs --grants-only 2>&1)"; then
  echo 'FAIL: deploy accepted an admin-capable worker membership.' >&2; exit 1
fi
grep -q 'membership must be one non-admin SET ROLE edge' <<<"$membership_error" \
  || { echo "FAIL: unexpected admin-membership refusal: $membership_error" >&2; exit 1; }
owner_psql -d trimmy -c \
  "REVOKE ADMIN OPTION FOR $red_day_capability_role FROM $red_day_worker_role" >/dev/null
owner_psql -d trimmy -c "GRANT $social_moderator_role TO $runtime_role" >/dev/null
if moderator_membership_error="$(node tool/runtime/apply-migrations.mjs --grants-only 2>&1)"; then
  echo 'FAIL: deploy accepted API membership in the moderator role.' >&2; exit 1
fi
grep -q 'social moderator role has unsafe membership' <<<"$moderator_membership_error" \
  || { echo "FAIL: unexpected moderator-membership refusal: $moderator_membership_error" >&2; exit 1; }
owner_psql -d trimmy -c "REVOKE $social_moderator_role FROM $runtime_role" >/dev/null

echo '--- deployment rejects historical plain owners across API and red-day functions'
plain_function_owner=trimmy_plain_function_owner
owner_psql -d trimmy -c \
  "CREATE ROLE $plain_function_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS; ALTER FUNCTION trimmy.career_complete_mission(uuid,text,text,uuid,timestamptz) OWNER TO $plain_function_owner; ALTER FUNCTION trimmy.career_red_day_activate() OWNER TO $plain_function_owner; ALTER FUNCTION trimmy.social_reason_moderation_put(uuid,bigint,text,text,text) OWNER TO $plain_function_owner" >/dev/null
if owner_drift_error="$(node tool/runtime/apply-migrations.mjs --grants-only 2>&1)"; then
  echo 'FAIL: deploy accepted function owners that cannot bypass FORCE RLS.' >&2; exit 1
fi
grep -q 'Every Trimmy security-definer, API or red-day internal function must be owned' <<<"$owner_drift_error" \
  || { echo "FAIL: unexpected function-owner refusal: $owner_drift_error" >&2; exit 1; }
owner_psql -d trimmy -c \
  "ALTER FUNCTION trimmy.career_complete_mission(uuid,text,text,uuid,timestamptz) OWNER TO $owner_role; ALTER FUNCTION trimmy.career_red_day_activate() OWNER TO $owner_role; ALTER FUNCTION trimmy.social_reason_moderation_put(uuid,bigint,text,text,text) OWNER TO $owner_role; DROP ROLE $plain_function_owner" >/dev/null

echo '--- grants-only reconciliation removes stale API and worker internal authority'
owner_psql -d trimmy -c \
  "GRANT EXECUTE ON FUNCTION trimmy.career_server_mission_complete(uuid,text,uuid,timestamptz), trimmy.career_red_day_activate() TO $runtime_role, $red_day_worker_role; GRANT EXECUTE ON FUNCTION trimmy.practice_current_user() TO $runtime_role, $social_moderator_role; GRANT EXECUTE ON FUNCTION trimmy.social_bind_verified_x_identity_internal(uuid,text,text,timestamptz), trimmy.social_rate_windows_prune(timestamptz,integer) TO $runtime_role; GRANT SELECT, INSERT, UPDATE, DELETE ON trimmy.paper_reset_receipts, trimmy.career_reason_privacy, trimmy.career_reason_privacy_receipts, trimmy.invitations, trimmy.provider_identities, trimmy.social_friendships, trimmy.social_blocks, trimmy.social_reason_reports TO $runtime_role; GRANT SELECT ON trimmy.invitations TO $social_moderator_role" >/dev/null
reconciled="$(node tool/runtime/apply-migrations.mjs --grants-only)"
echo "$reconciled"
[[ "$(owner_psql -d trimmy -Atc "SELECT has_function_privilege('$runtime_role','trimmy.career_server_mission_complete(uuid,text,uuid,timestamptz)','EXECUTE') OR has_function_privilege('$runtime_role','trimmy.career_red_day_activate()','EXECUTE') OR has_function_privilege('$red_day_worker_role','trimmy.career_server_mission_complete(uuid,text,uuid,timestamptz)','EXECUTE') OR has_function_privilege('$red_day_worker_role','trimmy.career_red_day_activate()','EXECUTE')")" == 'f' ]] \
  || { echo 'FAIL: grants-only left stale internal red-day authority.' >&2; exit 1; }
[[ "$(owner_psql -d trimmy -Atc "SELECT has_table_privilege('$runtime_role','trimmy.paper_reset_receipts','SELECT') OR has_table_privilege('$runtime_role','trimmy.paper_reset_receipts','INSERT') OR has_table_privilege('$runtime_role','trimmy.paper_reset_receipts','UPDATE') OR has_table_privilege('$runtime_role','trimmy.paper_reset_receipts','DELETE')")" == 'f' ]] \
  || { echo 'FAIL: grants-only left direct paper-reset receipt authority.' >&2; exit 1; }
[[ "$(owner_psql -d trimmy -Atc "SELECT has_table_privilege('$runtime_role','trimmy.career_reason_privacy','SELECT') OR has_table_privilege('$runtime_role','trimmy.career_reason_privacy','INSERT') OR has_table_privilege('$runtime_role','trimmy.career_reason_privacy','UPDATE') OR has_table_privilege('$runtime_role','trimmy.career_reason_privacy','DELETE') OR has_table_privilege('$runtime_role','trimmy.career_reason_privacy_receipts','SELECT') OR has_table_privilege('$runtime_role','trimmy.career_reason_privacy_receipts','INSERT') OR has_table_privilege('$runtime_role','trimmy.career_reason_privacy_receipts','UPDATE') OR has_table_privilege('$runtime_role','trimmy.career_reason_privacy_receipts','DELETE')")" == 'f' ]] \
  || { echo 'FAIL: grants-only left direct reason-privacy table authority.' >&2; exit 1; }
[[ "$(owner_psql -d trimmy -Atc "SELECT has_function_privilege('$runtime_role','trimmy.practice_current_user()','EXECUTE') OR has_function_privilege('$runtime_role','trimmy.social_bind_verified_x_identity_internal(uuid,text,text,timestamptz)','EXECUTE') OR has_function_privilege('$runtime_role','trimmy.social_rate_windows_prune(timestamptz,integer)','EXECUTE') OR has_table_privilege('$runtime_role','trimmy.invitations','SELECT') OR has_table_privilege('$runtime_role','trimmy.provider_identities','SELECT') OR has_table_privilege('$runtime_role','trimmy.social_friendships','SELECT') OR has_table_privilege('$runtime_role','trimmy.social_blocks','SELECT') OR has_table_privilege('$runtime_role','trimmy.social_reason_reports','SELECT')")" == 'f' ]] \
  || { echo 'FAIL: grants-only left stale direct relationship authority.' >&2; exit 1; }
[[ "$(owner_psql -d trimmy -Atc "SELECT has_function_privilege('$social_moderator_role','trimmy.practice_current_user()','EXECUTE') OR has_table_privilege('$social_moderator_role','trimmy.invitations','SELECT') OR NOT has_function_privilege('$social_moderator_role','trimmy.social_reason_moderation_put(uuid,bigint,text,text,text)','EXECUTE')")" == 'f' ]] \
  || { echo 'FAIL: grants-only did not restore exact moderator authority.' >&2; exit 1; }

echo '--- explicit activation is the final grants-only deployment step'
export TRIMMY_MIGRATION_ACTIVATE_RED_DAY=true
activation="$(node tool/runtime/apply-migrations.mjs --grants-only)"
echo "$activation"
grep -q 'Red-day evidence is active' <<<"$activation" || { echo 'FAIL: explicit red-day activation did not complete.' >&2; exit 1; }
export TRIMMY_MIGRATION_ACTIVATE_RED_DAY=false

echo '--- second run is idempotent'
second="$(node tool/runtime/apply-migrations.mjs)"
echo "$second"
grep -q 'No pending migrations' <<<"$second" || { echo 'FAIL: expected no pending migrations.' >&2; exit 1; }

echo '--- owner retention job uses verified TLS and one bounded batch'
retention="$(node tool/runtime/run-guest-retention.mjs --batch 17)"
echo "$retention"
grep -q 'lock=acquired' <<<"$retention" || { echo 'FAIL: retention did not acquire its lock.' >&2; exit 1; }
grep -q 'sourceAttemptsDeleted=0 rateWindowsDeleted=0 sessionsRedacted=0 hasMore=false' <<<"$retention" \
  || { echo 'FAIL: unexpected retention result.' >&2; exit 1; }

echo '--- the v6 payload constraint from 0008 is present'
owner_psql -d trimmy -Atc \
  "SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'practice_progress_progress_check'" \
  | grep -q "'6'" || { echo 'FAIL: v6 is not admitted by the applied schema.' >&2; exit 1; }

echo '--- the restricted runtime role received working privileges but no DDL'
runtime_conn="host=localhost port=$port dbname=trimmy user=$runtime_role sslmode=verify-full sslrootcert=$runtime_dir/tls/ca.crt"
export PGPASSWORD="$runtime_password"
ssl_state="$("$postgres_bin/psql" -X -Atc 'SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()' "$runtime_conn")"
[[ "$ssl_state" == 't' ]] || { echo 'FAIL: runtime role did not connect over TLS.' >&2; exit 1; }
PGHOST=localhost PGPORT="$port" PGDATABASE=trimmy PGUSER="$runtime_role" \
TRIMMY_READINESS_CA_FILE="$runtime_dir/tls/ca.crt" \
  node --import tsx --input-type=module <<'NODE'
import {readFileSync} from 'node:fs';
import pg from 'pg';
import {PostgresRelationshipSafetyReadiness} from
  './apps/api/src/postgres-relationship-safety-readiness.ts';

const pool = new pg.Pool({
  ssl: {ca: readFileSync(process.env.TRIMMY_READINESS_CA_FILE, 'utf8'),
    rejectUnauthorized: true},
  application_name: 'trimmy-relationship-readiness-test',
  connectionTimeoutMillis: 5_000,
  max: 1,
});
try {
  if (!await new PostgresRelationshipSafetyReadiness(pool).ready()) {
    throw new Error('Relationship safety readiness rejected the final runtime grants.');
  }
} finally {
  await pool.end();
}
NODE
"$postgres_bin/psql" -X -Atc 'SELECT count(*) FROM trimmy.practice_progress' "$runtime_conn" >/dev/null \
  || { echo 'FAIL: runtime role cannot read its granted table.' >&2; exit 1; }
if "$postgres_bin/psql" -X -Atc 'CREATE TABLE trimmy.should_not_exist(id int)' "$runtime_conn" >/dev/null 2>&1; then
  echo 'FAIL: runtime role was able to run DDL.' >&2; exit 1
fi
if "$postgres_bin/psql" -X -Atc 'SELECT count(*) FROM trimmy.financial_intents' "$runtime_conn" >/dev/null 2>&1; then
  echo 'FAIL: runtime role reached a financial table.' >&2; exit 1
fi
if "$postgres_bin/psql" -X -Atc 'SELECT count(*) FROM trimmy.career_profiles' "$runtime_conn" >/dev/null 2>&1; then
  echo 'FAIL: runtime role reached Career tables directly.' >&2; exit 1
fi
if "$postgres_bin/psql" -X -Atc 'SELECT count(*) FROM trimmy.career_mission_completions' "$runtime_conn" >/dev/null 2>&1; then
  echo 'FAIL: runtime role reached Career mission history directly.' >&2; exit 1
fi
if "$postgres_bin/psql" -X -Atc 'SELECT count(*) FROM trimmy.product_launch_action_receipts' "$runtime_conn" >/dev/null 2>&1; then
  echo 'FAIL: runtime role reached product launch receipts directly.' >&2; exit 1
fi
if "$postgres_bin/psql" -X -Atc 'SELECT count(*) FROM trimmy.paper_reset_receipts' "$runtime_conn" >/dev/null 2>&1; then
  echo 'FAIL: runtime role reached paper reset receipts directly.' >&2; exit 1
fi
if "$postgres_bin/psql" -X -Atc 'SELECT count(*) FROM trimmy.career_reason_privacy' "$runtime_conn" >/dev/null 2>&1; then
  echo 'FAIL: runtime role reached Career reason privacy directly.' >&2; exit 1
fi
if "$postgres_bin/psql" -X -Atc 'SELECT count(*) FROM trimmy.career_reason_privacy_receipts' "$runtime_conn" >/dev/null 2>&1; then
  echo 'FAIL: runtime role reached Career reason privacy receipts directly.' >&2; exit 1
fi
for social_table in invitations provider_identities social_profiles social_friendships social_blocks social_reason_reports social_reason_moderation social_rate_windows; do
  if "$postgres_bin/psql" -X -Atc "SELECT count(*) FROM trimmy.$social_table" "$runtime_conn" >/dev/null 2>&1; then
    echo "FAIL: runtime role reached $social_table directly." >&2; exit 1
  fi
done
if "$postgres_bin/psql" -X -Atc 'SELECT * FROM trimmy.guest_auth_retention(1)' "$runtime_conn" >/dev/null 2>&1; then
  echo 'FAIL: runtime role invoked owner-only guest retention.' >&2; exit 1
fi
if "$postgres_bin/psql" -X -Atc \
  "SELECT trimmy.career_server_mission_complete('00000000-0000-4000-8000-000000000001'::uuid,'hold-through-red-day','00000000-0000-4000-8000-000000000002'::uuid,clock_timestamp())" \
  "$runtime_conn" >/dev/null 2>&1; then
  echo 'FAIL: runtime role reached the internal Career evidence seam.' >&2; exit 1
fi
if "$postgres_bin/psql" -X -Atc 'SELECT trimmy.career_red_day_activate()' \
  "$runtime_conn" >/dev/null 2>&1; then
  echo 'FAIL: runtime role reached the owner-only red-day activation seam.' >&2; exit 1
fi
if "$postgres_bin/psql" -X -Atc 'SELECT * FROM trimmy.career_red_day_candidates(1)' \
  "$runtime_conn" >/dev/null 2>&1; then
  echo 'FAIL: runtime role reached a red-day worker function.' >&2; exit 1
fi
"$postgres_bin/psql" -X -Atc \
  "SELECT outcome FROM trimmy.career_summary_get('00000000-0000-4000-8000-000000000001'::uuid)" \
  "$runtime_conn" | grep -q '^account_missing$' \
  || { echo 'FAIL: runtime role cannot execute the Career summary function.' >&2; exit 1; }
"$postgres_bin/psql" -X -Atc \
  "SELECT outcome FROM trimmy.career_missions_get('00000000-0000-4000-8000-000000000001'::uuid)" \
  "$runtime_conn" | grep -q '^account_missing$' \
  || { echo 'FAIL: runtime role cannot execute the Career missions function.' >&2; exit 1; }
"$postgres_bin/psql" -X -Atc \
  "SELECT outcome FROM trimmy.product_launch_advance('00000000-0000-4000-8000-000000000001'::uuid,'00000000-0000-4000-8000-000000000002'::uuid,repeat('0',64),1,'paper-trade-confirmed',NULL)" \
  "$runtime_conn" | grep -q '^principal_conflict$' \
  || { echo 'FAIL: runtime role cannot execute the product launch function.' >&2; exit 1; }
"$postgres_bin/psql" -X -Atc \
  "BEGIN; SELECT set_config('trimmy.practice_user_id','00000000-0000-4000-8000-000000000001',true); SELECT outcome FROM trimmy.paper_desk_reset('00000000-0000-4000-8000-000000000001'::uuid,'00000000-0000-4000-8000-000000000002'::uuid,repeat('0',64),0); COMMIT" \
  "$runtime_conn" | grep -q '^account_missing$' \
  || { echo 'FAIL: runtime role cannot execute the paper reset function.' >&2; exit 1; }
"$postgres_bin/psql" -X -Atc \
  "BEGIN; SELECT set_config('trimmy.practice_user_id','00000000-0000-4000-8000-000000000001',true); SELECT outcome FROM trimmy.career_reason_privacy_get('00000000-0000-4000-8000-000000000001'::uuid); COMMIT" \
  "$runtime_conn" | grep -q '^account_missing$' \
  || { echo 'FAIL: runtime role cannot execute the reason privacy function.' >&2; exit 1; }
"$postgres_bin/psql" -X -Atc \
  "BEGIN; SELECT set_config('trimmy.practice_user_id','00000000-0000-4000-8000-000000000001',true); SELECT outcome FROM trimmy.career_trade_reason_list('00000000-0000-4000-8000-000000000001'::uuid,'self',NULL,NULL,NULL,NULL,20); COMMIT" \
  "$runtime_conn" | grep -q '^account_missing$' \
  || { echo 'FAIL: runtime role cannot execute the Career reason list function.' >&2; exit 1; }
"$postgres_bin/psql" -X -Atc \
  "BEGIN; SELECT set_config('trimmy.practice_user_id','00000000-0000-4000-8000-000000000001',true); SELECT outcome FROM trimmy.social_invitation_list('00000000-0000-4000-8000-000000000001'::uuid,NULL,'open',NULL,NULL,20); COMMIT" \
  "$runtime_conn" | grep -q '^account_missing$' \
  || { echo 'FAIL: runtime role cannot execute the social invitation list function.' >&2; exit 1; }
if "$postgres_bin/psql" -X -Atc \
  "SELECT trimmy.social_bind_verified_x_identity_internal('00000000-0000-4000-8000-000000000001'::uuid,'1','x',clock_timestamp())" \
  "$runtime_conn" >/dev/null 2>&1; then
  echo 'FAIL: runtime role reached the internal X binding function.' >&2; exit 1
fi
if "$postgres_bin/psql" -X -Atc 'SELECT trimmy.practice_current_user()' \
  "$runtime_conn" >/dev/null 2>&1; then
  echo 'FAIL: runtime role reached the internal current-principal helper.' >&2; exit 1
fi
unset PGPASSWORD

echo '--- relationship identity, friendship, block and closure constraints hold'
owner_psql -d trimmy -f "$infra_dir/tests/relationship-safety-constraints.sql" >/dev/null
export PGPASSWORD="$runtime_password"

echo '--- the dedicated red-day login has no direct grants and the bounded CLI enters its capability over TLS'
worker_conn="host=localhost port=$port dbname=trimmy user=$red_day_worker_role sslmode=verify-full sslrootcert=$runtime_dir/tls/ca.crt"
export PGPASSWORD="$red_day_worker_password"
worker_ssl="$("$postgres_bin/psql" -X -Atc 'SELECT ssl FROM pg_stat_ssl WHERE pid=pg_backend_pid()' "$worker_conn")"
[[ "$worker_ssl" == 't' ]] || { echo 'FAIL: red-day worker did not connect over TLS.' >&2; exit 1; }
if "$postgres_bin/psql" -X -Atc 'SELECT * FROM trimmy.career_red_day_candidates(1)' \
  "$worker_conn" >/dev/null 2>&1; then
  echo 'FAIL: NOINHERIT worker login executed without SET ROLE.' >&2; exit 1
fi
worker_count="$("$postgres_bin/psql" -X -qAtc \
  "SET ROLE $red_day_capability_role; SELECT count(*) FROM trimmy.career_red_day_candidates(1)" \
  "$worker_conn")"
[[ "$worker_count" == '0' ]] || { echo 'FAIL: worker capability invocation was unexpected.' >&2; exit 1; }

npm run build:backend >/dev/null
export TRIMMY_RED_DAY_DATABASE_URL="postgresql://$red_day_worker_role:$red_day_worker_password@localhost:$port/trimmy"
export TRIMMY_RED_DAY_DATABASE_CA_FILE="$runtime_dir/tls/ca.crt"
export TRIMMY_RED_DAY_WORKER_ROLE="$red_day_worker_role"
export TRIMMY_RED_DAY_CAPABILITY_ROLE="$red_day_capability_role"
export TRIMMY_RED_DAY_ASSET_CATALOG_JSON='{"apple":"AAPL"}'
export TRIMMY_RED_DAY_CANDIDATE_LIMIT=1
export TRIMMY_RED_DAY_EVIDENCE_BATCH_LIMIT=1
export TOKENS_API_KEY=fixture-key-never-used
worker_result="$(node tool/runtime/career-red-day-worker.mjs --once)"
echo "$worker_result"
grep -q '"skipped":false' <<<"$worker_result" || { echo 'FAIL: red-day worker CLI did not run.' >&2; exit 1; }
grep -q '"failureCodes":\[\]' <<<"$worker_result" || { echo 'FAIL: red-day worker CLI result is incomplete.' >&2; exit 1; }

echo '--- worker runner rejects direct and transitive extra capability ingress'
owner_psql -d trimmy -c \
  "CREATE ROLE $rogue_role LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS; GRANT $red_day_capability_role TO $rogue_role" >/dev/null
if ingress_error="$(node tool/runtime/career-red-day-worker.mjs --once 2>&1)"; then
  echo 'FAIL: worker runner accepted a second direct capability member.' >&2; exit 1
fi
grep -q 'Only the dedicated red-day worker may reach the capability role' <<<"$ingress_error" \
  || { echo "FAIL: unexpected worker direct-ingress refusal: $ingress_error" >&2; exit 1; }
owner_psql -d trimmy -c \
  "REVOKE $red_day_capability_role FROM $rogue_role; CREATE ROLE $bridge_role NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS; GRANT $red_day_capability_role TO $bridge_role; GRANT $bridge_role TO $rogue_role" >/dev/null
if ingress_error="$(node tool/runtime/career-red-day-worker.mjs --once 2>&1)"; then
  echo 'FAIL: worker runner accepted an indirect capability member chain.' >&2; exit 1
fi
grep -q 'Only the dedicated red-day worker may reach the capability role' <<<"$ingress_error" \
  || { echo "FAIL: unexpected worker indirect-ingress refusal: $ingress_error" >&2; exit 1; }
owner_psql -d trimmy -c \
  "REVOKE $bridge_role FROM $rogue_role; REVOKE $red_day_capability_role FROM $bridge_role; DROP ROLE $bridge_role; DROP ROLE $rogue_role" >/dev/null
owner_psql -d trimmy -c \
  "GRANT $red_day_capability_role TO $red_day_worker_role WITH ADMIN OPTION" >/dev/null
if membership_error="$(node tool/runtime/career-red-day-worker.mjs --once 2>&1)"; then
  echo 'FAIL: worker runner accepted an admin-capable membership.' >&2; exit 1
fi
grep -q 'membership must be one non-admin SET ROLE edge' <<<"$membership_error" \
  || { echo "FAIL: unexpected worker admin-membership refusal: $membership_error" >&2; exit 1; }
owner_psql -d trimmy -c \
  "REVOKE ADMIN OPTION FOR $red_day_capability_role FROM $red_day_worker_role" >/dev/null

echo '--- plaintext is refused by the server'
if "$postgres_bin/psql" -X -Atc 'SELECT 1' \
  "host=localhost port=$port dbname=trimmy user=$runtime_role sslmode=disable" >/dev/null 2>&1; then
  echo 'FAIL: a plaintext connection succeeded.' >&2; exit 1
fi
export PGPASSWORD="$red_day_worker_password"
if "$postgres_bin/psql" -X -Atc 'SELECT 1' \
  "host=localhost port=$port dbname=trimmy user=$red_day_worker_role sslmode=disable" >/dev/null 2>&1; then
  echo 'FAIL: red-day worker plaintext connection succeeded.' >&2; exit 1
fi
unset PGPASSWORD

echo '--- a database ahead of this build is refused, not downgraded'
owner_psql -d trimmy -c \
  "INSERT INTO trimmy.schema_migrations(version) VALUES ('0009_from_a_newer_build')" >/dev/null
if ahead="$(node tool/runtime/apply-migrations.mjs 2>&1)"; then
  echo "FAIL: expected a refusal, got: $ahead" >&2; exit 1
fi
grep -q 'does not know' <<<"$ahead" || { echo "FAIL: unexpected message: $ahead" >&2; exit 1; }
echo "$ahead"
owner_psql -d trimmy -c \
  "DELETE FROM trimmy.schema_migrations WHERE version = '0009_from_a_newer_build'" >/dev/null

echo '--- grants-only mode refreshes privileges without applying DDL'
grants="$(node tool/runtime/apply-migrations.mjs --grants-only)"
echo "$grants"
grep -q "Grants refreshed for $runtime_role" <<<"$grants" || { echo 'FAIL: grants-only did not report success.' >&2; exit 1; }

echo 'PASS: migrations apply to a TLS-only PostgreSQL, stay idempotent, grant the restricted role correctly and refuse a newer schema; private cluster will be removed.'
