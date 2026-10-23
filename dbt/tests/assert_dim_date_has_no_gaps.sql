-- The calendar must contain every day between its first and last date.
select first_day, last_day, days_found
from (
    select min(date_day) as first_day, max(date_day) as last_day, count(*) as days_found
    from {{ ref('dim_date') }}
) x
where days_found <> last_day - first_day + 1
