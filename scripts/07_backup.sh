#!/usr/bin/env bash
# Back up the whole database to backups/rental_dwh_<date>.dump (compressed, restorable with pg_restore).
# Keeps the newest 14 files. The dump holds REAL data: backups/ is git-ignored, keep it out of cloud folders that are shared.
#
#   bash scripts/07_backup.sh
#   Restore into a NEW database (never over the live one by accident):
#     createdb rental_dwh_restored
#     pg_restore --no-owner -d rental_dwh_restored backups/rental_dwh_2026-10-23_0900.dump
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB="${RENTAL_DB:-${PGDATABASE:-rental_dwh}}"
mkdir -p "$ROOT/backups"
FILE="$ROOT/backups/${DB}_$(date +%Y-%m-%d_%H%M).dump"
pg_dump -Fc -d "$DB" -f "$FILE"
echo "Backup written: $FILE ($(du -h "$FILE" | cut -f1))"
# keep the newest 14
ls -1t "$ROOT"/backups/${DB}_*.dump 2>/dev/null | tail -n +15 | while read -r old; do rm -f "$old"; done
