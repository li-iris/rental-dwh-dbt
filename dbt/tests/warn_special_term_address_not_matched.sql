{{ config(severity='warn') }}
-- Business follow-up: a special clause is for an address that is not one of the managed properties.
select address_raw, term_text
from {{ ref('fact_special_term') }}
where property_id is null
