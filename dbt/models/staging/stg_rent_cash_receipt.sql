{{ config(materialized='view') }}

-- Cash rent collected from tenants, from the sheet "房租cash".
-- Only the structured month blocks (collected -> handed in -> banked) are read here.
-- Earlier months were written as free text ("7.29 Sam") and stay in bronze.
-- A property is written once on its first row; the room rows below it inherit that address.

with src as (
    select
        t.*,
        sum((c_d ~ '^[0-9]')::int) over (partition by _file_sha256 order by _row_number) as address_group
    from {{ source('bronze', 'rent_cash') }} t
    where _row_number > 1
),

with_address as (
    select *,
        max(case when c_d ~ '^[0-9]' then trim(c_d) end)
            over (partition by _file_sha256, address_group) as address_raw
    from src
),

headers as (
    select _file_sha256, c_ao as oct_header, c_ba as nov_header
    from {{ source('bronze', 'rent_cash') }}
    where _row_number = 1
),

blocks as (
    select w._file_sha256, w._row_number, w.address_raw, w.c_u as room_label_raw,
           h.oct_header as month_header,
           w.c_ao as amount_raw, w.c_ap as collected_by_raw, w.c_aq as collected_raw,
           w.c_ar as handover_gap_raw, w.c_as as handover_raw,
           w.c_at as bank_gap_raw, w.c_au as banked_raw, w.c_av as banked_by_raw, w.c_aw as note
    from with_address w join headers h using (_file_sha256)
    union all
    select w._file_sha256, w._row_number, w.address_raw, w.c_u,
           h.nov_header,
           w.c_ba, w.c_bb, w.c_bc, w.c_bd, w.c_be, w.c_bf, w.c_bg, w.c_bh, w.c_bi
    from with_address w join headers h using (_file_sha256)
)

select
    _file_sha256                                                       as source_file_sha256,
    _row_number                                                        as source_row_number,
    address_raw,
    nullif(trim(room_label_raw), '')                                   as room_label,
    substring(month_header from '([0-9]{1,2})月')::int                  as rent_month_number,
    case when amount_raw ~ '^-?[0-9]+(\.[0-9]+)?$' then amount_raw::numeric end   as cash_amount,
    trim(collected_by_raw)                                             as collected_by_raw,
    case when collected_raw ~ '^\d{4}-\d{2}-\d{2}' then left(collected_raw, 10)::date end as collected_date,
    case when handover_raw  ~ '^\d{4}-\d{2}-\d{2}' then left(handover_raw, 10)::date end  as handover_date,
    case when handover_gap_raw ~ '^[0-9]+(\.0+)?$' then handover_gap_raw::numeric::int end as handover_gap_days_written,
    case when banked_raw    ~ '^\d{4}-\d{2}-\d{2}' then left(banked_raw, 10)::date end    as banked_date,
    case when bank_gap_raw  ~ '^[0-9]+(\.0+)?$' then bank_gap_raw::numeric::int end        as bank_gap_days_written,
    trim(banked_by_raw)                                                as banked_by_raw,
    nullif(trim(note), '')                                             as note
from blocks
where amount_raw ~ '^-?[0-9]+(\.[0-9]+)?$'
