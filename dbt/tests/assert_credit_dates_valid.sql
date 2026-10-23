-- Fails if the end date is before the start date, or days does not match the dates.
select *
from {{ ref('stg_rent_credit') }}
where end_date < start_date
   or days <> (end_date - start_date + 1)
