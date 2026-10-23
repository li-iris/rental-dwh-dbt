{{ config(materialized='view') }}

-- One row per RMB (Chinese yuan) rent payment received, from the sheet "人民币入账".

select
    _file_sha256                                       as source_file_sha256,
    _row_number                                        as source_row_number,
    trim(c_a)                                          as address_raw,
    case when c_b ~ '^-?[0-9]+(\.[0-9]+)?$' then c_b::numeric end   as rmb_amount,
    case when c_c ~ '^-?[0-9]+(\.[0-9]+)?$' then c_c::numeric end   as exchange_rate,
    case when c_d ~ '^-?[0-9]+(\.[0-9]+)?$' then c_d::numeric end   as aud_amount,
    case when c_e ~ '^\d{4}-\d{2}-\d{2}' then left(c_e, 10)::date end as receipt_date,
    trim(c_f)                                          as detail,
    trim(c_g)                                          as recorded_by_raw,
    case when c_h ~ '^\d{4}-\d{2}-\d{2}' then left(c_h, 10)::date end as recorded_date,
    case when c_i ~ '^-?[0-9]+(\.[0-9]+)?$' then c_i::numeric end   as weekly_rent,
    case when c_j ~ '^-?[0-9]+(\.[0-9]+)?$' then c_j::numeric end   as days_paid,
    case when c_k ~ '^-?[0-9]+(\.[0-9]+)?$' then c_k::numeric end   as rent_due_aud,
    case when c_l ~ '^-?[0-9]+(\.[0-9]+)?$' then c_l::numeric end   as rent_difference_aud
from {{ source('bronze', 'rmb_receipts') }}
where _row_number > 1
  and c_a is not null
