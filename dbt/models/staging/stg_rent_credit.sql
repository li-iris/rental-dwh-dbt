{{ config(materialized='view') }}

select
    _file_sha256          as source_file_sha256,
    _row_number           as source_row_number,
    trim(c_b)             as address_raw,
    c_c::numeric          as weekly_rent,
    c_d::int              as days,
    c_e::date             as start_date,
    c_f::date             as end_date,
    c_g::numeric          as credit_amount,
    c_h::numeric          as booked_amount,
    c_i                   as note,
    c_j                   as booked_by,
    c_k::date             as booked_date
from {{ source('bronze', 'rent_credit') }}
where _row_number > 2
  and c_b is not null
