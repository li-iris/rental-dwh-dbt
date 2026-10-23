{{ config(materialized='view') }}

-- Price list of parking spaces and garages by building, from the sheet "车库车位信息表":
-- one list priced per month (with bond and access type) and one priced per week.
-- Phone, email and tenant names in the same sheet are deliberately not read.

with src as (
    select * from {{ source('bronze', 'garage_parking') }}
    where _row_number > 1
)

select
    _source_file                              as source_file,
    _file_sha256                              as source_file_sha256,
    _row_number                               as source_row_number,
    'monthly_price_list'                      as source_list,
    trim(c_p)                                 as address_raw,
    'month'                                   as price_period,
    {{ to_num('c_q') }}                       as price,
    {{ to_num('c_r') }}                       as bond,
    nullif(trim(c_s), '')                     as access_type_raw,
    nullif(trim(c_t), '')                     as cover_type_raw
from src
where c_p ~ '^[0-9]' and {{ to_num('c_q') }} is not null

union all
select
    _source_file, _file_sha256, _row_number,
    'weekly_price_list',
    trim(c_x),
    'week',
    {{ to_num('c_y') }},
    {{ to_num('c_z') }},
    nullif(trim(c_aa), ''),
    null
from src
where c_x ~ '^[0-9]' and {{ to_num('c_y') }} is not null
