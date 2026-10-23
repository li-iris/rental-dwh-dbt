{{ config(materialized='view') }}

-- The source sheet has 3 repeated column groups (3 check rounds) in one row.
-- This model turns each round into its own row (unpivot).

with base as (
    select
        _file_sha256   as source_file_sha256,
        _row_number    as source_row_number,
        trim(c_a)      as address_raw,
        c_b, c_c, c_d,
        c_f, c_g, c_h, c_i, c_j,
        c_l, c_m, c_n, c_o, c_p
    from {{ source('bronze', 'rent_reconciliation') }}
    where _row_number > 1
      and c_a is not null
),

unpivoted as (
    select source_file_sha256, source_row_number, address_raw,
           1 as check_round,
           c_b as check_date_raw, c_c as checked_by, c_d as result_note,
           null::text as payment_method, null::text as resolution
    from base
    union all
    select source_file_sha256, source_row_number, address_raw,
           2, c_f, c_g, c_h, c_i, c_j
    from base
    union all
    select source_file_sha256, source_row_number, address_raw,
           3, c_l, c_m, c_n, c_o, c_p
    from base
)

select
    source_file_sha256,
    source_row_number,
    address_raw,
    check_round,
    case when check_date_raw ~ '^\d{4}-\d{2}-\d{2}'
         then left(check_date_raw, 10)::date end   as check_date,
    check_date_raw,
    trim(checked_by)     as checked_by,
    trim(result_note)    as result_note,
    payment_method,
    resolution
from unpivoted
where check_date_raw is not null
   or result_note is not null
