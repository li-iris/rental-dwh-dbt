{{ config(severity='warn') }}
-- Warning only: the number of days written in the sheet is not (end date - start date + 1).
select coverage_id, account, period_start, period_end, days_written, days_counted
from {{ ref('fact_bank_ledger_coverage') }}
where days_written is distinct from days_counted
