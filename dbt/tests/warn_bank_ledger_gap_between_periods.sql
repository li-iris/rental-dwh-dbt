{{ config(severity='warn') }}
-- Warning only: for one account, a period does not start the day after the previous one ended.
-- A positive gap = days never entered into the books; a negative gap = days entered twice.
select coverage_id, account, period_start, period_end, gap_days_before
from {{ ref('fact_bank_ledger_coverage') }}
where gap_days_before is not null
  and gap_days_before <> 0
