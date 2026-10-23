{{ config(severity='warn') }}
-- Business follow-up: the moving job date has no year (or is empty), so the job cannot be placed on a calendar.
select address_raw, date_raw
from {{ ref('fact_moving_job') }}
where not date_is_complete
