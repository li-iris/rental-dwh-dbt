-- How many water bills are in each follow-up status, and how much money is involved.
select
    follow_up_status,
    count(*)               as bills,
    sum(amount)            as total_amount,
    max(days_past_due)     as max_days_past_due
from {{ ref('stg_water_bill') }}
group by follow_up_status
