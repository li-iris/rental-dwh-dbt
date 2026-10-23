{{ config(severity='warn') }}
-- Warning only: a new tenant is booked but nobody wrote down when the old tenant actually moved out.
-- Deadlines then fall back to the planned contract end date.
select case_id, address_raw, old_contract_end_date, new_move_in_date
from {{ ref('fact_turnover_case') }}
where has_next_tenant
  and actual_move_out_date is null
