# Portfolio notes

## One-paragraph summary
Rebuilt a small rental agency's spreadsheet-based operations into a PostgreSQL data warehouse using dbt: 18 Excel sheets
→ bronze/silver/gold layers, ~60 models, ~230 automated data tests, business rules stored as versioned seed tables,
a constrained and audited direct-entry schema, one-command refresh, run history, backups and CI.

## Resume bullets (pick 3-4)
- Designed a bronze/silver/gold PostgreSQL warehouse with dbt (60+ models, 230+ tests) over 18 inconsistent Excel sheets; every raw cell kept as text with file hash and row number so loads are idempotent and auditable.
- Parsed free-text business data in SQL (rent changes, month-day dates without a year, addresses carried down blank rows) and refused to guess missing values; unresolved cells surface as typed warnings.
- Encoded 20+ business rules (payment terms, legal recovery windows, inspection limits) as seed tables with owner and source, so thresholds change without touching SQL and statuses recalculate on every run.
- Built a direct-entry schema with check constraints, foreign keys and a generic audit trigger (before/after JSON), plus least-privilege roles (entry-only, read-only reporting).
- Automated operations: one-command refresh with locking and exit codes, layout-change guard for the Excel inputs, run-history snapshots, scheduled backups, Excel problem lists for non-technical staff, GitHub Actions CI on synthetic data, dbt docs on GitHub Pages.

## 90-second talk track
1. *Problem*: a tiny agency ran everything in Excel; the same thing was written five different ways and nobody could say what was overdue.
2. *Approach*: keep raw data untouched (bronze), clean in views (silver), model facts and dimensions (gold). Every rule is data, every doubt is a test.
3. *Hard part*: dates without years and free-text rents. I would rather show "unknown" than invent a date, so the tests turn doubt into a follow-up list the owner can answer.
4. *Operations*: the owner types new data into constrained tables; one command rebuilds everything; a problem list goes to Excel; history shows if things get better.
5. *What I would do next*: bank-feed ingestion, incremental models, row-level security, orchestration with Airflow.

## Questions to be ready for
- Why dbt views in silver and tables in gold? (cheap to change; gold is queried a lot)
- How do you stop a duplicated load? (hash + sheet delete-then-insert in one transaction, row-count reconciliation)
- Why text in bronze? (no load ever fails because of a typo; typing happens in silver)
- How do you handle a column inserted in Excel? (layout fingerprint, exit code 3)
- What is not tested? (see README "Honest limits")
