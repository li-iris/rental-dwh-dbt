{{ config(severity='warn') }}
-- Business follow-up: an inspection or notice is for an address that is not one of the managed properties (sold, ended, or a typo).
select notice_type, address_raw, notice_date
from {{ ref('fact_inspection_notice') }}
where property_id is null
