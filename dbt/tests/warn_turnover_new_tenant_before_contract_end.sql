{{ config(severity='warn') }}
-- Warning only: the new tenant arrives before the old contract ends. Either the old tenant left early
-- (and the move-out date was not recorded) or a date is wrong.
select case_id, address_raw, old_contract_end_date, actual_move_out_date, new_move_in_date, vacancy_gap_days
from {{ ref('fact_turnover_case') }}
where vacancy_gap_days < 0
