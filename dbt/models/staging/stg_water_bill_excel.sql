{{ config(materialized='view') }}

-- One row per water bill (property x billing period) from the sheet "water".
-- A property is written once, on its first bill; the next bills of the same property leave the address empty, so it is carried down.
-- The date columns are text like "Sam2025.6.10" (company paid) or "6.18casey" (month.day only);
-- the missing year of month.day cells is the one closest to the day the company paid the bill.

with src as (
    select *,
        nullif(regexp_replace(trim(c_a), '[(（].*$', ''), '') as address_here
    from {{ source('bronze', 'water_bill') }}
    where _row_number > 1
),

grouped as (
    select *,
        count(case when address_here ~ '^[0-9]' then 1 end)
            over (partition by _source_file order by _row_number) as grp
    from src
),

carried as (
    select *,
        max(case when address_here ~ '^[0-9]' then address_here end)
            over (partition by _source_file, grp) as address_raw
    from grouped
),

kept as (
    select *,
        regexp_split_to_array(trim(c_c), '\s*(?:--|-|\sto\s)\s*') as period_parts
    from carried
    where address_raw is not null
      and (nullif(trim(c_d), '') is not null or nullif(trim(c_f), '') is not null
           or nullif(trim(c_g), '') is not null or nullif(trim(c_h), '') is not null)
),

parsed as (
    select *,
        case when array_length(period_parts, 1) = 2 then trim(period_parts[1]) end as start_raw,
        case when array_length(period_parts, 1) = 2 then trim(period_parts[2]) end as end_raw,
        {{ first_date('c_f') }} as company_paid_date
    from kept
),

dated as (
    select *,
        {{ parse_loose_date('start_raw') }} as period_start,
        {{ parse_loose_date('end_raw') }}   as period_end
    from parsed
)

select
    md5(_file_sha256 || '|' || _row_number::text || '|water') as water_bill_id,
    _source_file   as source_file,
    _row_number    as source_row_number,
    address_raw,
    nullif(trim(c_c), '')                              as period_text,
    period_start,
    period_end,
    {{ to_num('trim(c_d)') }}                          as amount,
    nullif(trim(c_e), '')                              as water_bill_copy_text,
    (c_e ~ '^(有|是|已)')                               as has_water_bill_copy,
    company_paid_date,
    nullif(trim(c_f), '')                              as company_paid_text,
    nullif(trim(c_g), '')                              as invoice_text,
    {{ nearest_month_day('c_g', 'coalesce(company_paid_date, period_end)') }} as invoice_sent_date,
    (c_g ~ '退房报告')                                  as settled_in_exit_report,
    (select sa.staff_name from regexp_matches(coalesce(c_g, ''), '[A-Za-z]+', 'g') t(m)
       join {{ ref('staff_aliases') }} sa on sa.alias = lower(t.m[1]) limit 1) as invoice_sent_by,
    nullif(trim(c_h), '')                              as tenant_paid_text,
    {{ nearest_month_day('c_h', 'coalesce(company_paid_date, period_end)') }} as tenant_paid_date,
    nullif(trim(c_i), '')                              as checked_text
from dated
