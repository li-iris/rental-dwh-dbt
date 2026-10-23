select
    property_id,
    property_key,
    unit_number,
    street_number,
    street_name,
    is_rented_by_room,
    master_address_raw
from {{ source('raw', 'dim_property') }}
