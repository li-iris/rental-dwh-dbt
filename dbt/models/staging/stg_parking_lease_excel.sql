{{ config(materialized='view') }}

-- Parking spaces and garages with the contract status written beside them, from the sheet "车库车位信息表".
-- Three lists sit side by side. Next to each space is either "合同已到期" (contract expired), a date
-- (assumed to be the contract end date), or "没有租客消息" (no tenant information).
-- Tenant contact details in the same sheet (phone, email) are deliberately not read.

with src as (
    select * from {{ source('bronze', 'garage_parking') }}
    where _row_number > 1
),

lists as (
    select _source_file, _file_sha256, _row_number, 'parking_list' as source_list, c_a as addr, c_b as status_raw from src
    union all
    select _source_file, _file_sha256, _row_number, 'garage_list', c_e, c_f from src
    union all
    select _source_file, _file_sha256, _row_number, 'no_tenant_list', c_j, c_k from src
)

select
    _source_file                                                       as source_file,
    _file_sha256                                                       as source_file_sha256,
    _row_number                                                        as source_row_number,
    source_list,
    trim(addr)                                                         as address_raw,
    {{ parking_address_standard('addr') }}                             as address_standard,
    case when addr ~* 'gar' then 'garage' else 'parking_space' end     as space_kind,
    case
        when status_raw ~ '已到期'            then 'expired'
        when status_raw ~ '没有租客'          then 'no_tenant_info'
        when {{ first_date('status_raw') }} is not null then 'dated'
        else 'other'
    end                                                                as lease_status,
    {{ first_date('status_raw') }}                                     as contract_end_date,
    trim(status_raw)                                                   as status_raw
from lists
where addr is not null
