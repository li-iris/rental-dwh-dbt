{{ config(severity='warn') }}
-- Business follow-up: a paperwork case is for an address that is not one of the managed properties (for example a property already handed back).
select process, address_raw
from {{ ref('fact_process_case') }}
where property_id is null
