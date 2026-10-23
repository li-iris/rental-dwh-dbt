# Typing data in directly (Navicat)

From now on new records can be typed straight into the database. Everything you type goes into schema `entry`.
The refresh (`bash scripts/run_all.sh`) merges the typed rows with the rows from the old Excel workbooks and rebuilds the finished tables.

## Rules of the road

1. Type only into schema `entry`. The finished tables (schema `gold`) are rebuilt on every refresh; changes made there are lost.
2. Add the address to `entry.property` first. Every other entry table picks its address from that list, so a typo cannot create a ghost property.
3. A house let room by room: add one row per room, e.g. `12 Smith St Room 1`, `12 Smith St Room 2`, and tick `is_rented_by_room`.
4. Dates are real dates (`2026-10-23`). Money is a number without a symbol. A refund is a negative amount.
5. Never delete to "fix" a mistake you want to keep a trace of; edit the row instead. Every insert, update and delete is written to `entry.audit_log` with the user and the time.
6. Use the staff name exactly as in `dim_staff` (first name). An unknown name is reported as a data error (exit code 2) at the next refresh, so it is caught early.

## The tables

| Table | One row is | Required columns |
|---|---|---|
| `entry.property` | a property (or one room of a room-rented house) | `address` |
| `entry.tenancy` | one tenant on one lease | `address`, `tenant_name` (rent is `weekly_rent`) |
| `entry.rent_payment` | one payment received | `address`, `paid_date`, `amount`, `method` |
| `entry.water_bill` | one water bill | `address`, `amount` |
| `entry.utility_bill` | one electricity or gas bill | `address`, `bill_type` |
| `entry.inspection_notice` | one inspection or notice | `address`, `notice_type`, `notice_date` |
| `entry.special_term` | one special clause | `address`, `term_text` |
| `entry.parking_lease` | one parking space or garage | `address`, `space_label` |
| `entry.moving_job` | one moving job | `address`, `job_date` |
| `entry.moving_job_item` | one item type of one job | `moving_job_entry_id`, `item_code`, `quantity` |

## What the database refuses

The tables have checks built in, so wrong data is rejected at the moment you save it: a lease that ends before it starts, a negative rent,
an invoice date without a payment date, a payment date in the future, an unknown lease type, a second row for the same parking space.
The message names the rule that was broken.

## Accounts

`boss_entry` can read the finished tables and type into `entry`; it cannot see raw data (phone numbers, e-mail) or change anything else.
`report_viewer` can only read the finished tables. Create or reset them with `bash scripts/08_create_users.sh`.
