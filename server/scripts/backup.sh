#!/bin/sh
set -eu

if [ -z "${DATABASE_URL:-}" ]; then
  echo "DATABASE_URL is required" >&2
  exit 1
fi

backup_directory="${BACKUP_DIRECTORY:-./backups}"
retention_days="${BACKUP_RETENTION_DAYS:-14}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "$backup_directory"
umask 077
pg_dump --format=custom --no-owner --no-acl "$DATABASE_URL" \
  > "$backup_directory/tivuq-$timestamp.dump"
find "$backup_directory" -type f -name 'tivuq-*.dump' \
  -mtime "+$retention_days" -delete

echo "Backup created: $backup_directory/tivuq-$timestamp.dump"
