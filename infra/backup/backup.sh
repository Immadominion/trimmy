#!/bin/sh
# One dump, uploaded, then exit. Railway runs this on a schedule.
#
# The database certificate is issued by a private authority, so the bundle
# arrives as a variable and is written here: verification stays strict rather
# than being downgraded to an unverified encrypted session.
set -eu

: "${DATABASE_URL:?DATABASE_URL is required}"
: "${BACKUP_BUCKET:?BACKUP_BUCKET is required}"
: "${AWS_ENDPOINT_URL:?AWS_ENDPOINT_URL is required}"

stamp="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
file="trimmy-${stamp}.dump"
umask 077

if [ -n "${DATABASE_CA:-}" ]; then
  printf '%s\n' "$DATABASE_CA" > /tmp/ca.crt
  export PGSSLROOTCERT=/tmp/ca.crt
  export PGSSLMODE=verify-full
else
  # Refuse to quietly take an unverified backup path.
  echo 'DATABASE_CA is required so the dump verifies the database certificate.' >&2
  exit 1
fi

echo "Dumping database at ${stamp}."
pg_dump "$DATABASE_URL" --format=custom --no-owner --no-privileges --file="/tmp/${file}"

bytes="$(wc -c < "/tmp/${file}" | tr -d ' ')"
[ "$bytes" -gt 0 ] || { echo 'The dump is empty; nothing will be uploaded.' >&2; exit 1; }
# A custom-format dump starts with the PGDMP magic. A file that does not is not
# a backup, and uploading it would only create a false belief that one exists.
head -c 5 "/tmp/${file}" | grep -q 'PGDMP' || { echo 'The dump is not a PostgreSQL archive.' >&2; exit 1; }

echo "Uploading ${file} (${bytes} bytes)."
aws s3 cp "/tmp/${file}" "s3://${BACKUP_BUCKET}/${file}" --endpoint-url "$AWS_ENDPOINT_URL" --only-show-errors
rm -f "/tmp/${file}" /tmp/ca.crt
echo "Backup complete: ${file}"
