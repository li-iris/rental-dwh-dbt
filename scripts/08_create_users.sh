#!/usr/bin/env bash
# Create (or reset the passwords of) the two accounts defined in sql/20_roles.sql.
#   bash scripts/08_create_users.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB="${RENTAL_DB:-${PGDATABASE:-rental_dwh}}"
read -r -s -p "Password for boss_entry (reads gold, types into entry): " BOSS_PW; echo
read -r -s -p "Password for report_viewer (reads gold only): " VIEWER_PW; echo
if [ -z "$BOSS_PW" ] || [ -z "$VIEWER_PW" ]; then echo "Passwords must not be empty."; exit 1; fi
psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -v boss_pw="$BOSS_PW" -v viewer_pw="$VIEWER_PW" -f "$ROOT/sql/20_roles.sql"
echo "Done. In Navicat: new PostgreSQL connection, host = this computer's address, port 5432, database $DB, user boss_entry."
echo "Run this script again after adding new schemas, and keep the passwords out of the repository."
