select
    parking_lease_id,
    property_id,
    address_raw,
    space_kind,
    source_list,
    lease_status,
    contract_end_date,
    contract_status
from {{ source('raw', 'fact_parking_lease') }}
