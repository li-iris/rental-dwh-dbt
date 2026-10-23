-- One row per property (a unit, a house, or a house rented room by room).
-- Properties are the union of all source sheets, except parking spaces: those are linked to a property
-- only when one matches, and never create a property of their own.
select
    md5(property_key)                                          as property_id,
    property_key,
    max(unit)                                                  as unit_number,
    max(street_number)                                         as street_number,
    max(street_token)                                          as street_name,
    bool_or(room_label is not null)                            as is_rented_by_room,
    bool_or(src = 'reconciliation')                            as in_reconciliation,
    coalesce(min(address_raw) filter (where src = 'reconciliation'),
             min(address_raw))                                 as master_address_raw
from {{ ref('stg_address_parsed') }}
where src not in ('parking_lease', 'inspection_list', 'special_terms', 'process_list', 'water_list', 'utility_list', 'moving_list')
group by property_key
