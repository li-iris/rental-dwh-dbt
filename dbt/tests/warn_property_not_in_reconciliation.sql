{{ config(severity='warn') }}
-- Warning only: property appears in another sheet but not in the reconciliation list.
-- Either it is not managed any more, or the address has a typo that needs a fix in the seed.
select property_key,
       string_agg(distinct src, ', ') as found_in,
       min(address_raw)               as example_address
from {{ ref('stg_address_parsed') }}
where property_key not in (
    select property_key from {{ ref('stg_address_parsed') }} where src = 'reconciliation'
)
group by property_key
