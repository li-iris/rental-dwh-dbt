# Running and looking after the warehouse

## Refresh everything

```bash
bash scripts/run_all.sh
```

Steps: (1) create/update the `entry` and `history` schemas, (2) read the Excel files in `raw_private/` and check their layout,
(3) `dbt seed`, (4) `dbt run`, (5) `dbt test --store-failures`, (6) write `reports/problem_list.xlsx`, `reports/management_report.xlsx`,
(7) record the run in `history`, (8) back up the database.

| Option | Effect |
|---|---|
| `REPORT_DATE=2026-01-13 bash scripts/run_all.sh` | Judge overdue / expiry as of that day instead of today |
| `SKIP_EXCEL=1 bash scripts/run_all.sh` | Do not re-read the Excel files (use what is already loaded; use this once everything is typed in) |
| `SKIP_BACKUP=1 bash scripts/run_all.sh` | No backup this run |

Exit code 0 = finished (follow-up warnings are normal), 1 = a step failed, 2 = finished but an error-level check failed (broken data).
Each run writes `logs/run_<date>.log`. Only one run can be active at a time.

## Run it automatically (macOS)

```bash
bash scripts/09_schedule_macos.sh install 06:30        # every day at 06:30
bash scripts/09_schedule_macos.sh install 06:30 1      # Mondays only
bash scripts/09_schedule_macos.sh status
bash scripts/09_schedule_macos.sh uninstall
```

The Mac must be switched on and Postgres running; if it was asleep at that time the job runs when it wakes.
Output of the scheduler itself goes to `logs/launchd.out.txt` and `logs/launchd.err.txt`.

## Backup and restore

`run_all.sh` calls `scripts/07_backup.sh` which writes `backups/rental_dwh_<date>.dump` and keeps the newest 14.
Restore into a new database (never straight over the live one):

```bash
createdb rental_dwh_restored
pg_restore --no-owner -d rental_dwh_restored backups/rental_dwh_2026-10-23_0900.dump
```

Backups contain real data. They are git-ignored; do not put them in a shared cloud folder. Copy them to a second disk now and then:
a backup on the same computer does not survive that computer breaking.

## Accounts for other people

```bash
bash scripts/08_create_users.sh
```

Creates `boss_entry` (reads finished tables, types into `entry`) and `report_viewer` (reads finished tables only). Neither can see
the raw layer (phone numbers, e-mail). Navicat: new PostgreSQL connection, this computer's address, port 5432, database `rental_dwh`.
To let another computer connect, Postgres must listen on the network and `pg_hba.conf` must allow it; do this only on a trusted network.

## Looking at what changed

```sql
select * from history.run_log order by run_id desc;                                   -- one row per refresh
select * from history.problem_count where run_id = (select max(run_id) from history.run_log) order by failures desc;
select * from history.water_bill_status where water_bill_id = '...' order by run_id;  -- how one bill moved over time
select * from entry.audit_log order by audit_id desc limit 50;                        -- who typed or changed what
```

## Excel layout check

Columns are read by position. `scripts/02b_check_layout.py` compares the header rows of every sheet with `config/expected_layout.json`
(created on the first run). If someone inserts a column, the refresh stops with a message naming the sheet and column.
After an intended change, update the models that read those columns, then `python scripts/02b_check_layout.py raw_private/bronze_csv --accept`.
`config/` is git-ignored because it holds header text from the real workbooks.

## Data dictionary

`python scripts/10_generate_data_dictionary.py` writes `docs/DATA_DICTIONARY.md` and `reports/data_dictionary.xlsx` from the live database.
Meanings come from `docs/table_notes.csv` and `docs/column_notes.csv`; columns without a note are listed with an empty meaning.

## Housekeeping

- `DBT_ENGINE_MANAGE_STATE=0` is set by `run_all.sh` to switch off the dbt state plugin.
- Seeds are always refreshed with `--full-refresh`, so adding a column to a seed CSV just works.
- Never edit tables in `gold`; they are rebuilt on every run. Edit the Excel files, the seed CSVs, or the `entry` tables.
