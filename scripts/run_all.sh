#!/usr/bin/env bash
# One command to refresh everything:
#   Excel -> bronze -> dbt (seeds, models, checks) -> problem list + reports -> run history -> backup
#
#   bash scripts/run_all.sh                 normal refresh
#   REPORT_DATE=2026-01-13 bash scripts/run_all.sh     judge overdue/expiry as of that day instead of today
#   SKIP_EXCEL=1 bash scripts/run_all.sh    do not re-read the Excel files (use what is already in bronze)
#   SKIP_BACKUP=1 bash scripts/run_all.sh   no backup this time
#
# Exit code 0 = finished (follow-up warnings are normal). 1 = a step failed. 2 = finished, but a data ERROR check failed.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p logs reports backups
LOG="logs/run_$(date +%Y-%m-%d_%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

if [ -f "$ROOT/.venv/bin/activate" ]; then
    # shellcheck disable=SC1091
    source "$ROOT/.venv/bin/activate"
fi
export DBT_ENGINE_MANAGE_STATE=0          # silences the dbt state plugin
PY="$(command -v python || command -v python3 || true)"
if [ -z "$PY" ]; then echo "python not found (activate the virtual environment: source .venv/bin/activate)"; exit 1; fi

# only one refresh at a time
LOCK="$ROOT/logs/.run_all.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
    echo "Another refresh is already running (remove $LOCK if that is not true)."; exit 1
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

STARTED=$(date +%s)
say() { echo; echo "=== $(date +%H:%M:%S)  $*"; }
fail() { echo; echo "FAILED at step: $1  (see $LOG)"; exit 1; }

DB="${RENTAL_DB:-${PGDATABASE:-rental_dwh}}"
VARS=()
if [ -n "${REPORT_DATE:-}" ]; then VARS=(--vars "{report_date: $REPORT_DATE}"); fi

say "1/8  Database objects for direct entry and run history"
psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -f sql/10_entry_schema.sql >/dev/null || fail "entry schema"
psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -f sql/30_history.sql      >/dev/null || fail "history schema"
if [ -f sql/21_entry_comments_zh.sql ]; then psql -X -q -d "$DB" -f sql/21_entry_comments_zh.sql >/dev/null 2>&1 || true; fi

if [ -z "${SKIP_EXCEL:-}" ] && ls raw_private/*.xlsx >/dev/null 2>&1; then
    say "2/8  Read the Excel files"
    "$PY" scripts/01_extract_to_csv.py raw_private || fail "extract Excel"
    "$PY" scripts/02b_check_layout.py raw_private/bronze_csv || fail "Excel layout changed"
    "$PY" scripts/02_load_bronze.py raw_private/bronze_csv "$DB" || fail "load bronze"
else
    say "2/8  Excel step skipped (SKIP_EXCEL set or no files in raw_private/)"
fi

cd dbt
say "3/8  dbt seed (rule tables)"
dbt seed --full-refresh || fail "dbt seed"
say "4/8  dbt run (rebuild the silver and gold tables)"
dbt run ${VARS[@]+"${VARS[@]}"} || fail "dbt run"
say "5/8  dbt test (automatic checks; failing rows are stored for the problem list)"
dbt test --store-failures ${VARS[@]+"${VARS[@]}"} > "../logs/last_dbt_test.txt" 2>&1
TEST_EXIT=$?
cat "../logs/last_dbt_test.txt" | tail -25
cd "$ROOT"
SUMMARY=$(grep -E "Done\. PASS=" logs/last_dbt_test.txt | tail -1)
P=$(echo "$SUMMARY" | sed -n 's/.*PASS=\([0-9]*\).*/\1/p'); W=$(echo "$SUMMARY" | sed -n 's/.*WARN=\([0-9]*\).*/\1/p'); E=$(echo "$SUMMARY" | sed -n 's/.*ERROR=\([0-9]*\).*/\1/p')
P=${P:-0}; W=${W:-0}; E=${E:-0}

say "6/8  Problem list and reports"
"$PY" scripts/05_export_problem_list.py   || echo "  (problem list failed - continuing)"
"$PY" scripts/04_export_management_report.py || echo "  (management report failed - continuing)"
if [ -f scripts/03_export_turnover_report.py ]; then "$PY" scripts/03_export_turnover_report.py || echo "  (turnover report failed - continuing)"; fi

say "7/8  Run history"
"$PY" scripts/06_record_history.py "$P" "$W" "$E" "${REPORT_DATE:+report date set to $REPORT_DATE}" || echo "  (history failed - continuing)"

if [ -z "${SKIP_BACKUP:-}" ]; then
    say "8/8  Backup"
    bash scripts/07_backup.sh || echo "  (backup failed - continuing)"
else
    say "8/8  Backup skipped"
fi

echo
echo "Finished in $(( $(date +%s) - STARTED )) seconds.  Checks: PASS=$P  WARN(follow-ups)=$W  ERROR=$E"
echo "Reports are in $ROOT/reports/   Log: $LOG"
if [ "$E" -gt 0 ] || { [ "$TEST_EXIT" -ne 0 ] && [ "$E" -eq 0 ] && [ -z "$SUMMARY" ]; }; then
    echo "!! At least one data ERROR check failed. Open logs/last_dbt_test.txt."; exit 2
fi
exit 0
