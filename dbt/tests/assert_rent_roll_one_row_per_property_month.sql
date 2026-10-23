-- fact_rent_roll_month must have exactly one row per property and month.
select property_id, month_start, count(*) as n
from {{ ref('fact_rent_roll_month') }}
group by property_id, month_start
having count(*) > 1
