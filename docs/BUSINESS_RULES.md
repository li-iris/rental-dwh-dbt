# Business rules used by the warehouse

The working lists leave many questions open (which file is newer, whether a rent is for a room or a whole unit, when a bill is late).
The warehouse answers them with the rules below. They follow how a small residential property-management agency in
New South Wales, Australia normally works, and where the law sets a number (water charges, inspections) the law's number is used.
The owner may change any rule: the numbers live in the seed `seeds/business_rules.csv`; change the number and refresh
(`bash scripts/run_all.sh`). Rules marked "in SQL" are written into a model and noted in its header comment.

This is a working default, not legal advice. Check NSW Fair Trading before relying on a legal limit.

| # | Area | Rule | Decided by | Where |
|---|---|---|---|---|
| 1 | Two workbook versions | The file without a date in its name is the newer one. Gold keeps the row from the newer version. | owner | seed `source_snapshot_order` |
| 2 | Room or whole unit | A weekly rent of 600 or less is one room; above 600 is the whole unit. A property let room by room has only room rents. | owner | seed `business_rules` (`whole_unit_rent_over`), `fact_rent_roll_month` |
| 3 | Same unit rent on several tenants | A whole-unit rent repeated on co-tenants counts once. | agency default | `fact_rent_roll_month` |
| 4 | Unclear rent | A lease with no rent is ignored when another lease has one. A whole-unit rent replaces room rents written beside it. Of two different whole-unit rents the newest lease wins. The result is kept apart in `expected_rent_with_rules_aud`. | agency default | `fact_rent_roll_month` |
| 5 | "Today" | Every overdue / expiry judgement is made against the report date, which is **the day dbt runs**, so figures are recalculated on every refresh. To look at the data as of another day: `REPORT_DATE=2026-01-13 bash scripts/run_all.sh`. The rent roll window ends with the current month. | agency default | `fact_turnover_step`, `fact_water_bill`, `fact_parking_lease`, `fact_rent_roll_month` |
| 6 | Water invoice | The tenant invoice should go out within 30 days after the agency pays the water bill. | agency default | seed (`water_invoice_due_days`) |
| 7 | Water payment | The tenant should pay within 21 days after the invoice is sent. NSW requires giving the tenant at least 21 days. | NSW rules | seed (`water_payment_due_days`) |
| 8 | Water: legal window | In NSW an agent may charge a tenant for water usage only if the tenant is asked within 3 months of the bill being issued. An unsent invoice older than 90 days is flagged `may_be_unrecoverable`. The bill-issue date is not in the lists, so the day the agency paid is used. | NSW rules | seed (`water_invoice_legal_limit_days`), `fact_water_bill` |
| 9 | Water settled at move-out | A water bill noted as settled in the exit report is closed. | agency default | `fact_water_bill` |
| 10 | Parking contracts | A dated contract whose end date is before the report date counts as expired. A renewal must be written into the sheet or the entry table. | agency default | `fact_parking_lease` |
| 11 | Move-out deadlines | Each step's deadline is the earlier of its own offset and the day before the next tenant moves in, for steps that must finish first. | agency default | seed `turnover_step_catalog` |
| 12 | Move-out date missing | The planned contract end date stands in for the actual move-out date. | agency default | `fact_turnover_case` |
| 13 | Step with no date | A step marked done with no date is done, date unknown. A blank step is "nothing recorded", not "done". | agency default | `stg_process_step_entry`, `fact_process_step` |
| 14 | Dates without a year | A year is chosen only by a stated rule (closest to a related date). Moving jobs with "month.day" only keep `job_date` empty. | agency default | staging models |
| 15 | Staff names | Spellings are mapped to one name in the seed `staff_aliases`. | agency default | seed `staff_aliases` |
| 16 | Addresses | Street name typos are fixed in the seed `street_token_fixes`. Sheets that only mention a property never create one. | agency default | seed `street_token_fixes`, `dim_property` |
| 17 | Contact details | Phone numbers, e-mail and similar stay in bronze only. | agency default | staging models |
| 18 | Routine inspections | At most 4 routine inspections per property in 12 months, and the tenant told at least 7 days before. | NSW rules | seed (`routine_inspection_max_per_year`, `routine_inspection_notice_days`), tests `warn_routine_inspections_exceed_yearly_limit`, `warn_routine_inspection_notice_too_short` |
| 19 | Lease expiry list | Leases ending within 60 days are listed for renewal (NSW needs 60 days' notice of a rent increase on renewal). | agency default | seed (`lease_expiry_warning_days`), management report |
| 20 | Where new data goes | New records are typed into the `entry` tables in Navicat. Entry rows are ranked above both Excel workbooks (`source_file = 'entry'`, rank 99), so a corrected record in `entry` wins. The workbooks remain the history. | owner's wish | `seeds/source_snapshot_order.csv`, staging models |
| 21 | Rent arrears (reference only) | In NSW rent must be 14 days overdue before a termination notice can be given. Not computed yet because it needs a weekly due-date schedule. | NSW rules | seed (`rent_arrears_notice_days`) |

## Where the NSW numbers come from

- Water usage charges: NSW Government, [Connection and supply of water to rental properties](https://www.nsw.gov.au/housing-and-construction/rules/connection-and-supply-of-water-to-rental-properties) (request payment within 3 months of the bill being issued; tenant gets at least 21 days to pay; a copy of the bill must be given).
- Rent arrears and water/utility arrears: Tenants' Union of NSW, [Overdue rent](https://www.tenants.org.au/factsheet-05-rent-arrears) (14 days overdue before a notice, 14 days' notice).
- Routine inspections (4 a year, 7 days' notice) are the usual NSW practice for agents; confirm the current numbers with NSW Fair Trading.

## Rules that still need a person

These stay as follow-ups in the problem list because no rule can decide them: a rent account check that ended as "issue", a lease whose dates are reversed or missing,
a vacancy credit larger than the expected rent, an address that matches no managed property, and a water bill past the 3-month window (bill it anyway or write it off).
