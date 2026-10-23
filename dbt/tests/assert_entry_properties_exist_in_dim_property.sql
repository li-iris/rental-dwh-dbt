-- Every address in the master list entry.property must become a row in dim_property.
select e.address
from {{ source('entry', 'property') }} e
left join {{ ref('stg_address_parsed') }} a on a.src = 'entry_property' and a.address_raw = e.address
left join {{ ref('dim_property') }} p on p.property_key = a.property_key
where p.property_id is null
