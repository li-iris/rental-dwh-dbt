{{ config(materialized='view') }}

-- The sheet "2.财务日常入账" records which date ranges of each money account have been entered into
-- the books. Four accounts sit side by side in one row; this model turns each into its own row.

with src as (
    select * from {{ source('bronze', 'bank_ledger_coverage') }}
    where _row_number > 1
),

unpivoted as (
    select _file_sha256, _row_number, 'company_card' as account,
           c_a as days_raw, c_b as start_raw, c_c as end_raw, c_d as by_raw, c_e as date_raw, c_f as flag_raw, null::text as note
    from src
    union all
    select _file_sha256, _row_number, 'sole_card',
           c_h, c_i, c_j, c_k, c_l, c_m, null
    from src
    union all
    select _file_sha256, _row_number, 'rmb',
           c_o, c_p, c_q, c_r, c_s, null, c_t
    from src
    union all
    select _file_sha256, _row_number, 'office_cash',
           c_w, c_x, c_y, c_z, c_aa, null, null
    from src
)

select
    _file_sha256                                                   as source_file_sha256,
    _row_number                                                    as source_row_number,
    account,
    case when start_raw ~ '^\d{4}-\d{2}-\d{2}' then left(start_raw, 10)::date end as period_start,
    case when end_raw   ~ '^\d{4}-\d{2}-\d{2}' then left(end_raw, 10)::date end   as period_end,
    case when days_raw  ~ '^[0-9]+(\.0+)?$' then days_raw::numeric::int end        as days_written,
    trim(by_raw)                                                   as recorded_by_raw,
    case when date_raw  ~ '^\d{4}-\d{2}-\d{2}' then left(date_raw, 10)::date end   as recorded_date,
    (trim(flag_raw) = '是')                                        as import_flag,
    nullif(trim(note), '')                                         as note
from unpivoted
where start_raw is not null
   or end_raw is not null
