{{ config(materialized='view') }}

-- Tenancies from the Excel workbooks (stg_tenancy_excel) plus tenancies typed into entry.tenancy.
-- Entry rows carry source_file = 'entry', which the seed source_snapshot_order ranks above every workbook.

select * from {{ ref('stg_tenancy_excel') }}

union all

select
    'entry'::text                                              as source_file,
    'entry'::text                                              as source_file_sha256,
    e.tenancy_entry_id::int                                    as source_row_number,
    e.created_at                                               as _loaded_at,
    e.address                                                  as address_raw,
    a.property_key,
    null::text                                                 as room_type_raw,
    e.lease_type,
    e.tenant_name,
    e.is_principal_tenant,
    null::text                                                 as term_raw,
    e.lease_start,
    e.lease_end,
    ((e.lease_start is not null)::int + (e.lease_end is not null)::int)::bigint as date_count,
    false                                                      as dates_written_reversed,
    case when e.weekly_rent is not null then 'single' end      as rent_pattern,
    e.weekly_rent                                              as unit_weekly_rent,
    null::numeric                                              as tenant_weekly_share,
    null::numeric                                              as rent_range_high,
    e.weekly_rent::text                                        as rent_raw,
    e.visa_expiry_date
from {{ source('entry', 'tenancy') }} e
left join {{ ref('stg_address_parsed') }} a
       on a.src = 'tenant_list' and a.address_raw = e.address
