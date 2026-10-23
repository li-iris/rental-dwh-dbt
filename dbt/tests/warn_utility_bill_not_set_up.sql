{{ config(severity='warn') }}
-- Business follow-up: a property is on the electricity / gas list but no bill period or amount is written yet.
select address_raw, bill_type_raw
from {{ ref('fact_utility_bill') }}
where is_not_set_up
