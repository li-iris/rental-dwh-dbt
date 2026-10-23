{{ config(severity='warn') }}
-- Business follow-up: the vacancy credit booked for a property in a month is larger than the rent the tenancy list expects.
-- Usually the tenancy list shows only one room's tenant, or the credit covers several rooms. Check which one.
select property_id, month_start, expected_rent_aud, vacancy_credit_aud
from {{ ref('fact_rent_roll_month') }}
where rent_basis in ('unit_rent', 'room_rent') and vacancy_credit_aud > expected_rent_aud + 1
