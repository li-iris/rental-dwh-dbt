# Rental Data Warehouse (dbt + PostgreSQL)

A small-business data warehouse rebuilt from three messy Excel workbooks (18 sheets) used by a rental agency to run
tenancies, rent collection, utility and water bills, inspections, parking and moving jobs.
**All data in this repository is invented.** The original project ran on a real agency's data, which never leaves the owner's computer.

```
Excel (18 sheets)  ->  bronze (everything as text)  ->  silver (cleaned views + rule seeds)  ->  gold (dim_ / fact_ / rpt_)
Direct entry (Navicat/psql) -> entry schema -----^                                              |
                                                                         problem list (Excel), dashboard, run history
```

## Run it in one command

```bash
docker compose up --build        # Postgres + the whole pipeline on invented data
# or, with Python 3.12 and a local Postgres:
pip install -r requirements.txt
export DBT_PROFILES_DIR=$PWD/dbt PGDATABASE=rental_dwh
make demo                        # invent data -> load -> dbt seed/run/test -> problem list -> history
make dashboard                   # docs_site/dashboard.html
```

CI (`.github/workflows/ci.yml`) does exactly this on every push and fails if any ERROR-level check fails.

## What is in it

| Area | What it shows |
|---|---|
| Ingestion | `scripts/01-02`: every cell loaded as text with file hash + row number; re-running never duplicates; a layout guard (`02b`) stops the load if someone inserts a column in Excel |
| Modelling | medallion layers; dimensional gold layer; ~60 dbt models, seeds for business rules, custom schema macro |
| Messy-data handling | free-text rents ("920, from 2.6 970"), dates without years ("6.18 Sam"), carried-down addresses, three lists side by side in one sheet - parsed in SQL, never guessed (a month.day cell with no year stays empty rather than getting an invented year) |
| Data quality | ~230 dbt tests: `assert_*` = must never fail (ERROR), `warn_*` = business follow-up (WARN). Failing rows are stored and exported as an Excel problem list with one sheet per issue |
| Business rules as data | `dbt/seeds/business_rules.csv`: due days, legal limits, thresholds - each with who decided it and why. Change a number, not SQL |
| Time-aware statuses | "overdue / expired / due soon" are judged against `gold.dim_report_date` (the day dbt runs, or `--vars report_date=...`), so a refresh recalculates everything |
| Direct entry | `entry` schema with constraints, foreign keys and an audit trigger (before/after JSON of every change); entry rows merge with Excel rows in staging |
| Operations | one-command refresh (`run_all.sh`), run history schema, backups, least-privilege roles, launchd scheduling |

Docs: [`docs/DATA_MODEL.md`](docs/DATA_MODEL.md), [`docs/ER.md`](docs/ER.md), [`docs/BUSINESS_RULES.md`](docs/BUSINESS_RULES.md),
[`docs/DATA_DICTIONARY.md`](docs/DATA_DICTIONARY.md), [`docs/OPERATIONS.md`](docs/OPERATIONS.md), [`docs/PORTFOLIO.md`](docs/PORTFOLIO.md).

## The synthetic data

`scripts/gen_synthetic.py` writes two workbooks with the same sheet titles and column positions as the originals,
with deliberate defects (overdue water bills, unclear rents, an expired parking contract, a property inspected five times in a year...).
Only 8 of the 18 sheets carry rows; the other 10 are header-only so the pipeline's table structure is complete.

## Honest limits

- Business rules (e.g. 90-day water recovery window, 21 days to pay, up to 4 routine inspections a year) follow NSW practice as understood by the author; this is not legal advice.
- The optional Airflow DAG in `airflow/` is a sketch and is not run in CI.
- Bank-transaction detail and rent arrears are not modelled.
