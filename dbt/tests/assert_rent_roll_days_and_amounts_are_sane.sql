-- Days with a tenancy cannot exceed the days in the month, and amounts cannot be negative.
select property_id, month_start, days_with_tenancy, expected_rent_aud
from {{ ref('fact_rent_roll_month') }}
where days_with_tenancy > (month_end - month_start + 1)
   or days_rent_unclear > days_with_tenancy
   or expected_rent_aud < 0 or cash_received_aud < 0 or rmb_received_aud < 0 or vacancy_credit_aud < 0
