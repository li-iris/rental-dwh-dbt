-- One row per room, only for properties that are rented room by room.
-- Room names are taken from the reconciliation sheet only: other sheets spell
-- the same room differently (mapping them is a later step).
select distinct
    md5(property_key || '|' || room_label)   as room_id,
    md5(property_key)                        as property_id,
    room_label
from {{ ref('stg_address_parsed') }}
where room_label is not null
  and src = 'reconciliation'
