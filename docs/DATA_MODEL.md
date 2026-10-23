# Rental data warehouse: data model

A Postgres warehouse (`rental_dwh`) rebuilt from three Excel workbooks that the property manager keeps by hand.
The goal is the same as the manager's: nothing missed and nothing wrong in the move-in / move-out process and the money around it.

## Layers

| Layer | Schema | What it holds | Built by |
|---|---|---|---|
| Bronze | `bronze` | Every sheet loaded as text, one row per Excel row, with source file, file hash and row number. Nothing is cleaned. Contact details stay here only. | `scripts/` (Python) |
| Silver | `silver` | Cleaned and typed views (`stg_*`) and small lookup tables (seeds). Addresses are parsed to one `property_key`; "month.day" cells get a year only by a stated rule. | dbt |
| Gold | `gold` | Dimensions (`dim_*`) and facts (`fact_*`) for reporting, plus reports (`rpt_*`). | dbt |
| Entry | `entry` | Tables people type into directly (Navicat). dbt only reads them and merges the rows with the workbook rows. Every change is logged in `entry.audit_log`. | people, `sql/10_entry_schema.sql` |
| History | `history` | One snapshot per refresh: check counts, row counts, water bill and parking states. | `scripts/06_record_history.py` |

## Keys and rules that apply everywhere

- **property_key** is `[unit/]street_number street_name`, built in `stg_address_parsed` from the address as written in any sheet. Typos in street names are fixed in the seed `street_token_fixes`. `dim_property` holds the managed properties; the paperwork, inspection, special clause, bill, moving and parking sheets are linked to it when the address matches, but they never create a property.
- **Two workbook versions** hold overlapping data. The seed `source_snapshot_order` ranks them and gold keeps the row from the higher rank. Rows typed into `entry` have `source_file = 'entry'` and the highest rank, so they win over both workbooks.
- **Excel and entry rows are merged in silver.** Each `stg_<x>` model is `stg_<x>_excel` (the workbook rows) `union all` the matching `entry` table, so everything downstream is unchanged.
- **No guessed dates.** A date without a year gets one only when a rule can be stated (for example "latest date not after the case's anchor date + 60 days"). Moving jobs with "month.day" only keep `job_date` empty.
- **Nothing silently lost.** Each model that collapses rows has a test that every silver row still reaches gold. Checklists are stored as the full case x step grid, so a step nobody recorded shows up as `is_missing` instead of not existing.
- **Contact data minimisation.** Phone numbers, e-mail addresses and similar details are not carried past bronze; phone-like numbers inside free text are replaced by `[number removed]`.

## Gold tables

| Area | Tables |
|---|---|
| Master data | `dim_property`, `dim_room`, `dim_property_profile`, `dim_room_profile`, `dim_property_item`, `dim_parking_space`, `dim_staff`, `dim_date` |
| Tenancies | `dim_tenancy` (one row per tenant per lease) |
| Rent and money | `fact_rent_credit`, `fact_rmb_receipt`, `fact_rent_cash_receipt`, `fact_rent_account_check`, `fact_bank_ledger_coverage`, `fact_rent_roll_month` |
| Move-out / move-in | `dim_turnover_step`, `fact_turnover_case`, `fact_turnover_step`, `rpt_turnover_open_items`, `fact_turnover_tenancy_candidate` |
| Paperwork checklists | `dim_process_step`, `fact_process_case`, `fact_process_step` (new tenant, renewal, contract transfer) |
| Inspections and clauses | `fact_inspection_notice` (routine, fire, other), `fact_special_term` |
| Bills and jobs | `fact_water_bill`, `fact_utility_bill`, `fact_moving_job`, `fact_moving_job_item`, `fact_parking_lease` |
| Typed-in money | `fact_rent_payment`, `rpt_rent_received_month` (expected rent next to every recorded receipt) |
| Rules | `dim_business_rule` (the numbers in force, who decided them, why) |

### Rent roll (`fact_rent_roll_month`)

One row per property and month: the rent the tenancy list expects, next to the money the workbooks record.
In `dim_tenancy` the weekly rent is written on every tenant row. The owner's rule is that a rent of 600 or less is the rent of one room and
a rent above 600 is the rent of the whole unit; a property that is rented room by room only has room rents, whatever the amount.
Each day is judged from the distinct leases active that day:

| rent_basis | Meaning | `expected_rent_aud` |
|---|---|---|
| `unit_rent` | One whole-unit rent, repeated for each co-tenant, counted once | filled |
| `room_rent` | Exactly one room rent | filled |
| `room_rents_estimated` | Several room rents added up; may be wrong if two people share a room | filled, not compared with payments |
| `unclear` | Missing rent, a whole-unit rent next to room rents, or two different whole-unit rents (see `unclear_reason`) | left empty |
| `no_tenancy` | Money was recorded but no tenancy covers the month | empty |

`expected_rent_with_rules_aud` fills the unclear months with the default rules in `docs/BUSINESS_RULES.md` and says which rule was used in
`rent_rules_applied`. Those amounts are assumptions until the owner confirms them.
The workbooks hold no bank transaction detail, so "no recorded payment" does not mean "not paid".

### Turnover to tenancy (`fact_turnover_tenancy_candidate`)

The turnover sheet has no tenant name and often no room. The table lists every tenancy of the same property with lease dates within
30 days of the turnover dates. `is_only_candidate` marks the links that are safe; the rest need a person to choose.

## Business rules

Where the sheets leave a question open, the warehouse uses default rules that a small rental agency would normally apply. They are listed in `docs/BUSINESS_RULES.md`; numbers such as due days live in the seed `business_rules` so they can be changed without touching SQL.

## Data quality as a deliverable

`dbt test` has two kinds of tests:

- **Errors** (`assert_*`, generic tests): the data is broken, for example a lost row, a period that ends before it starts, or a key that points at nothing.
- **Warnings** (`warn_*`, `severity='warn'`): the data is readable but needs a business follow-up, for example a bill paid by the company with no invoice recorded, a lease with reversed dates, or an inspection at an address that is not a managed property. These are the list to hand to the property manager.

## How to rebuild

```bash
cd dbt
dbt seed --full-refresh
dbt run
dbt test
```

Or everything at once (Excel, dbt, checks, reports, history, backup): `bash scripts/run_all.sh` (see `docs/OPERATIONS.md`).

By default every overdue / expiry judgement uses the day dbt runs. Useful variables: `--vars '{report_date: 2026-01-13}'` to look at the data
as of another day, `--vars '{rent_roll_start: 2025-07-01, rent_roll_through: 2026-01-31}'` to fix the rent roll window (default: from 2025-07-01 to the end of the current month).
