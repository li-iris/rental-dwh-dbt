{{ config(severity='warn') }}
-- Business follow-up: the billing period cell is empty or cannot be read as two dates.
select address_raw, period_text, amount
from {{ ref('fact_water_bill') }}
where period_start is null or period_end is null
