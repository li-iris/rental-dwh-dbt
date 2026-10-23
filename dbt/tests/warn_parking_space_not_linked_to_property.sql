{{ config(severity='warn') }}
-- Warning only: a parking space or garage is listed for a unit that is not one of the properties we manage
-- (or its address is written differently).
select address_raw, address_standard, source_list
from {{ ref('fact_parking_lease') }}
where property_id is null
