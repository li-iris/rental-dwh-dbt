-- One row per living space of a property (living room, master room, room 2-5) with orientation, furniture,
-- balcony and built-in wardrobe as written in the condition report columns of the sheet "Profit".

select
    md5(s.source_file_sha256 || '|' || s.source_row_number::text || '|' || s.space_code) as room_profile_id,
    p.property_id,
    s.address_raw,
    s.space_code,
    s.space_order,
    s.orientation_raw,
    s.furniture_raw,
    s.balcony_raw,
    s.wardrobe_raw
from {{ ref('stg_property_room_profile') }} s
left join {{ ref('stg_address_parsed') }} a
       on a.src = 'profit' and a.address_raw = s.address_raw
left join {{ ref('dim_property') }} p
       on p.property_key = a.property_key
