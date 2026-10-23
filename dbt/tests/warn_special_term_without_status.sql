{{ config(severity='warn') }}
-- Business follow-up: a special clause has no "carried out" note, so nobody has confirmed it was done.
select address_raw, term_text
from {{ ref('fact_special_term') }}
where not has_status
