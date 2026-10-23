{{ config(materialized='view') }}

-- Parking spaces and garages from the Excel workbooks plus spaces typed into entry.parking_lease.

select * from {{ ref('stg_parking_lease_excel') }}

union all

select
    'entry'::text                                    as source_file,
    'entry'::text                                    as source_file_sha256,
    e.parking_entry_id::int                          as source_row_number,
    'entry:' || e.space_label                        as source_list,
    e.address                                        as address_raw,
    e.address                                        as address_standard,
    e.space_kind,
    case when e.contract_end_date is not null then 'dated' else 'no_tenant_info' end as lease_status,
    e.contract_end_date,
    null::text                                       as status_raw
from {{ source('entry', 'parking_lease') }} e
