{{ config(materialized='view') }}

-- One row per property from the sheet named "Profit": room rents, contract tenants, agent, manager, bond,
-- building type and facilities. (Despite the sheet name it is a property information sheet, not a profit table.)
-- The stray block of cash-rent addresses further right (columns BT onwards) is not read here.

select
    _file_sha256                          as source_file_sha256,
    _row_number                           as source_row_number,
    trim(c_a)                             as address_raw,
    {{ to_num('c_b') }}                   as master_room_rent,
    {{ to_num('c_c') }}                   as room1_rent,
    {{ to_num('c_d') }}                   as room2_rent,
    {{ to_num('c_e') }}                   as room3_rent,
    {{ to_num('c_f') }}                   as room4_rent,
    {{ to_num('c_g') }}                   as room5_rent,
    {{ to_num('c_h') }}                   as garage_rent,
    {{ to_num('c_i') }}                   as bill_amount,
    {{ to_num('c_j') }}                   as total_rent_written,
    case when c_l ~ '^[0-9]+(\.0+)?$' then c_l::numeric::int end as room_count,
    nullif(trim(c_m), '')                 as contract_tenants_raw,
    {{ to_num('c_n') }}                   as referral_fee,
    nullif(trim(c_o), '')                 as agent_raw,
    nullif(trim(c_p), '')                 as manager_raw,
    {{ to_num('c_q') }}                   as bond,
    nullif(lower(trim(c_u)), '')          as building_type,
    case when c_v ~ '^[0-9]+(\.0+)?$' then c_v::numeric::int end as floor_number,
    case when c_w ~ '电梯' then 'lift' when c_w ~ '楼梯' then 'stairs' else nullif(trim(c_w), '') end as access_to_unit,
    case when c_x ~ '煤气' then 'gas' when c_x ~ '电' then 'electric' else nullif(trim(c_x), '') end   as cooker_type,
    nullif(trim(c_y), '')                 as building_access,
    nullif(trim(c_z), '')                 as parking_note,
    nullif(trim(c_aa), '')                as parking_access
from {{ source('bronze', 'profit_monthly') }}
where _row_number > 1
  and c_a is not null
