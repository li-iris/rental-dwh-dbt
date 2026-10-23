{{ config(materialized='view') }}

-- Items the company bought for properties (dryers, ovens, beds ...), from the sheet "房子物品list".
-- The sheet exists in several workbook versions; gold keeps the newest version of each item.
-- The move-in time is written loosely ("2023", "2024.2", "2024.3.15"), so the date keeps its precision.

with base as (
    select
        _source_file                       as source_file,
        _file_sha256                       as source_file_sha256,
        _row_number                        as source_row_number,
        trim(c_a)                          as address_raw,
        trim(c_b)                          as item_name,
        trim(c_c)                          as condition_raw,
        {{ to_num('c_d') }}                as price,
        trim(c_e)                          as installed_raw,
        nullif(trim(c_f), '')              as removed_note,
        regexp_match(trim(c_e), '^(20[0-9]{2})(?:[.\-]([0-9]{1,2}))?(?:[.\-]([0-9]{1,2}))?') as ymd
    from {{ source('bronze', 'property_items') }}
    where _row_number > 1
      and c_a is not null
)

select
    source_file, source_file_sha256, source_row_number,
    address_raw, item_name, condition_raw, price, installed_raw, removed_note,
    case
        when ymd is null then null
        when ymd[2] is null then make_date(ymd[1]::int, 1, 1)
        when ymd[2]::int not between 1 and 12 then null
        when ymd[3] is null then make_date(ymd[1]::int, ymd[2]::int, 1)
        when ymd[3]::int between 1 and 31
         and extract(month from make_date(ymd[1]::int, ymd[2]::int, 1) + (ymd[3]::int - 1)) = ymd[2]::int
            then make_date(ymd[1]::int, ymd[2]::int, 1) + (ymd[3]::int - 1)
    end                                                                as installed_date,
    case when ymd is null then null
         when ymd[2] is null then 'year'
         when ymd[3] is null then 'month'
         else 'day' end                                                as installed_date_precision
from base
