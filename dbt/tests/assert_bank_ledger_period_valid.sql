-- A covered period must end on or after the day it starts.
select coverage_id, account, period_start, period_end
from {{ ref('fact_bank_ledger_coverage') }}
where period_end < period_start
