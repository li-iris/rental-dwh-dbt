-- Fails if a check date exists in the source but could not be converted to a date.
select *
from {{ ref('stg_rent_reconciliation_check') }}
where check_date_raw is not null
  and check_date is null
