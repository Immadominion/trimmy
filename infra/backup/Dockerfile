# Scheduled offsite dump of the Trimmy database into the project's object store.
#
# It carries the PostgreSQL client for pg_dump and the AWS CLI for the upload,
# and nothing else. It never serves traffic and has no route.
FROM postgres:18-alpine
RUN apk add --no-cache aws-cli ca-certificates
COPY infra/backup/backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh
USER postgres
ENTRYPOINT ["/usr/local/bin/backup.sh"]
