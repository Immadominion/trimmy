#!/usr/bin/env bash
# Takes a logical backup of the hosted Trimmy database and verifies it arrived
# whole. Run it from the repository root with the Railway project linked:
#
#   bash tool/runtime/backup-database.sh [destination-directory]
#
# The dump is written to ~/trimmy-backups by default, with mode 600, named by
# the instant it was taken. It contains account rows, so treat it as personal
# data: keep it off shared storage and out of the repository.
#
# The database has no public endpoint, which is deliberate. The dump therefore
# runs inside the database container over its own loopback, and is streamed out
# through the existing SSH session rather than by exposing a port.
set -euo pipefail

service="${TRIMMY_BACKUP_SERVICE:-Postgres}"
environment="${TRIMMY_BACKUP_ENVIRONMENT:-production}"
destination="${1:-$HOME/trimmy-backups}"
stamp="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
remote="/tmp/trimmy-backup-$stamp.sql"
local_file="$destination/trimmy-$stamp.sql"

command -v railway >/dev/null || { echo 'The Railway CLI is required.' >&2; exit 1; }
mkdir -p "$destination"
chmod 700 "$destination"

# `railway ssh -- sh -c '...'` splits the script across argv, so a redirect
# inside it is silently mangled and the dump comes out empty. Feeding the script
# on standard input keeps it a single script, which is why this reads oddly.
remote_script="$(cat <<EOF
set -e
umask 077
PGPASSWORD="\$POSTGRES_PASSWORD" pg_dump -h 127.0.0.1 -U "\$POSTGRES_USER" -d "\$POSTGRES_DB" \
  --no-owner --no-privileges --format=plain > $remote
echo "bytes=\$(wc -c < $remote)"
EOF
)"

echo "Dumping $service ($environment) inside its container."
remote_bytes="$(printf '%s\n' "$remote_script" \
  | railway ssh --service "$service" --environment "$environment" -- sh -s 2>/dev/null \
  | sed -n 's/^bytes=//p' | tr -d '\r')"
[ -n "$remote_bytes" ] && [ "$remote_bytes" -gt 0 ] || { echo 'The dump produced nothing.' >&2; exit 1; }

umask 077
railway ssh --service "$service" --environment "$environment" -- cat "$remote" > "$local_file" 2>/dev/null
railway ssh --service "$service" --environment "$environment" -- rm -f "$remote" >/dev/null 2>&1 || true

local_bytes="$(wc -c < "$local_file" | tr -d ' ')"
if [ "$local_bytes" != "$remote_bytes" ]; then
  echo "Backup truncated in transit: $local_bytes of $remote_bytes bytes. Not keeping it." >&2
  rm -f "$local_file"
  exit 1
fi
tail -n 5 "$local_file" | grep -q 'PostgreSQL database dump complete' || {
  echo 'The backup does not end with its completion marker. Not keeping it.' >&2
  rm -f "$local_file"
  exit 1
}
chmod 600 "$local_file"

tables="$(grep -c 'CREATE TABLE' "$local_file" || true)"
echo "Backup written: $local_file"
echo "  bytes: $local_bytes, tables: $tables"
echo "Restore it into an empty PostgreSQL 18 database with:"
echo "  psql -d <empty-database> -v ON_ERROR_STOP=1 -f $local_file"
