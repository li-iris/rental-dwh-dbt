{{ config(severity='warn') }}
-- Business follow-up: money recorded in the workbooks for a property-month differs from the expected rent by more than $5.
-- Only months with a clear expected rent and at least one recorded payment are compared.
select property_id, month_start, expected_rent_aud, cash_received_aud, rmb_received_aud, vacancy_credit_aud, recorded_minus_expected_aud
from {{ ref('fact_rent_roll_month') }}
where abs(recorded_minus_expected_aud) > 5
