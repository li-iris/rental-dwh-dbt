{{ config(materialized='view') }}

-- One row per moving job (sheet "moving jobs"). Items moved are in stg_moving_job_item.
-- The date is written three ways: full date (13/11/2023, 2023-12-23), month.day only (5.26), or empty.
-- Month.day cells do not say which year, so job_date stays empty for them and date_is_complete is false
-- (the sheet is not in date order, so guessing the year would be a fabricated date).

with src as (
    select *, trim(c_a) as date_raw
    from {{ source('bronze', 'moving_jobs') }}
    where _row_number > 2 and c_b is not null
)

select
    md5(_file_sha256 || '|' || _row_number::text || '|moving') as moving_job_id,
    _source_file as source_file,
    _file_sha256 as source_file_sha256,
    _row_number  as source_row_number,
    trim(c_b)    as address_raw,
    nullif(date_raw, '') as date_raw,
    case
        when date_raw ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}' then left(date_raw, 10)::date
        when date_raw ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$' then to_date(date_raw, 'DD/MM/YYYY')
    end as job_date,
    (date_raw ~ '^[0-9]{1,2}\.[0-9]{1,2}$') as date_is_month_day_only,
    coalesce(date_raw ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}' or date_raw ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$', false) as date_is_complete,
    nullif(trim(c_c), '') as rooms_text,
    (regexp_match(c_c, '^[0-9]+'))[1]::int as bedrooms_first,
    nullif(trim(c_d), '') as stairs_text,
    nullif(trim(c_e), '') as work_time_text,
    -- total hours only when the cell is plain numbers added together, e.g. "8.5+4.5+7"
    case when trim(c_e) ~ '^[0-9. ]+(\+ *[0-9. ]+)*$'
         then (select sum(nullif(trim(p), '')::numeric) from unnest(string_to_array(trim(c_e), '+')) p) end as work_hours_total,
    nullif(trim(c_f), '') as others_text,
    nullif(trim(c_g), '') as crew_text,
    nullif(trim(c_w), '') as start_text,
    nullif(trim(c_x), '') as end_text,
    nullif(trim(c_y), '') as note_text,
    nullif(trim(c_z), '') as problem_text
from src
