{{ config(severity='warn') }}
-- Warning only: the account check note says something other than "no problem" (a difference, an unpaid
-- amount, a late payment ...). The owner should confirm each one was resolved.
select account_check_id, address_raw, check_round, check_date, result_note, resolution
from {{ ref('fact_rent_account_check') }}
where result_status = 'issue'
