{{ config(severity='warn') }}
-- Business follow-up: the case has no contract end / move-out / move-in date, so deadlines cannot be worked out.
select case_id, process, address_raw
from {{ ref('fact_process_case') }}
where anchor_date is null and not is_cancelled
