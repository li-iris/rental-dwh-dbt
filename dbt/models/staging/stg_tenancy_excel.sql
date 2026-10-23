-- One row per tenant per lease period, from the "0.Tenant" sheet.
-- Contact details (phone, email, WeChat, emergency contact) are deliberately NOT selected here.
-- Several workbook snapshots can contain the same tenancy: de-duplication happens in gold.

with base as (
    select
        _source_file                as source_file,
        _file_sha256                as source_file_sha256,
        _row_number                 as source_row_number,
        _loaded_at,
        trim(c_a)                   as address_raw,
        trim(c_b)                   as room_type_raw,
        trim(c_c)                   as tenant_name_raw,
        trim(c_d)                   as term_raw,
        trim(c_e)                   as rent_raw,
        trim(c_k)                   as visa_raw
    from {{ source('bronze', 'tenant_list') }}
    where _row_number > 1
      and c_a is not null
      and c_c is not null
),

-- The rent cell is free text. Numbers found in it:
rent_parts as (
    select source_file_sha256, source_row_number, rent_raw,
        substring(rent_raw from '^\s*\$?\s*([0-9]+(?:\.[0-9]+)?)')::numeric   as first_number,
        substring(rent_raw from '^\s*\$?\s*[0-9]+(?:\.[0-9]+)?\s*[-（(]\s*\$?\s*([0-9]+(?:\.[0-9]+)?)')::numeric
                                                                              as second_number,
        substring(rent_raw from '([0-9]+(?:\.[0-9]+)?)[^0-9]*$')::numeric     as last_number
    from base
),

-- Business rules (confirmed with the business owner):
--   plain / unchanged   : first number is the rent
--   rent_change         : "920, from 2.6 970" -> the LAST number is the current rent
--   negotiable_range    : "1150-1170" -> negotiable range, first number is the listed rent
--   tenant_share        : "990-495"   -> first = rent of the whole unit, second = this tenant's share
rent_kind as (
    select *,
        case
            when rent_raw is null                                                    then 'missing'
            when rent_raw ~ '^\s*[0-9]+(\.[0-9]+)?\s*(pw)?\s*$'                      then 'plain'
            when rent_raw ~ '租金不变'                                               then 'unchanged'
            when rent_raw ~ '起|号|to'                                               then 'rent_change'
            when second_number is not null and second_number >= first_number        then 'negotiable_range'
            when second_number is not null and second_number <  first_number        then 'tenant_share'
            else 'other' end as rent_pattern
    from rent_parts
),

-- every date written in the lease term, in the order it was written
term_dates as (
    select b.source_file_sha256, b.source_row_number, t.n,
           case when t.m[1] is not null
                then make_date(t.m[1]::int, t.m[2]::int, t.m[3]::int)        -- 2025.2.6
                else make_date(t.m[6]::int, t.m[5]::int, t.m[4]::int) end    -- 6/2/2025 (day first)
           as d
    from base b
    cross join lateral regexp_matches(b.term_raw,
        '(20[0-9]{2})\.(0?[1-9]|1[0-2])\.(0?[1-9]|[12][0-9]|3[01])|(0?[1-9]|[12][0-9]|3[01])/(0?[1-9]|1[0-2])/(20[0-9]{2})',
        'g') with ordinality as t(m, n)
),

term_summary as (
    select source_file_sha256, source_row_number,
           min(d)                                  as lease_start,
           max(d)                                  as lease_end,
           count(*)                                as date_count,
           (array_agg(d order by n))[1]            as first_date_written,
           (array_agg(d order by n))[count(*)]     as last_date_written
    from term_dates
    group by 1, 2
),

visa_dates as (
    select b.source_file_sha256, b.source_row_number,
           min(case when t.m[1] is not null
                    then make_date(t.m[1]::int, t.m[2]::int, t.m[3]::int)
                    else make_date(t.m[6]::int, t.m[5]::int, t.m[4]::int) end) as visa_expiry_date
    from base b
    cross join lateral regexp_matches(b.visa_raw,
        '(20[0-9]{2})\.(0?[1-9]|1[0-2])\.(0?[1-9]|[12][0-9]|3[01])|(0?[1-9]|[12][0-9]|3[01])/(0?[1-9]|1[0-2])/(20[0-9]{2})',
        'g') as t(m)
    group by 1, 2
)

select
    b.source_file,
    b.source_file_sha256,
    b.source_row_number,
    b._loaded_at,
    b.address_raw,
    a.property_key,
    b.room_type_raw,
    case when b.room_type_raw ~ '转租'       then 'sublet'
         when b.room_type_raw ~ '短租'       then 'short_term'
         when b.room_type_raw ~ '分[租组]'   then 'room_share'
         when b.room_type_raw ~ '整租|长租'  then 'whole_unit'
         when b.room_type_raw ~* 'studio'    then 'studio'
         else 'unspecified' end                                        as lease_type,
    regexp_replace(b.tenant_name_raw, '\s*[（(].*$', '')               as tenant_name,
    b.tenant_name_raw ~* 'principal'                                   as is_principal_tenant,
    b.term_raw,
    s.lease_start,
    s.lease_end,
    s.date_count,
    coalesce(s.first_date_written > s.last_date_written, false)        as dates_written_reversed,
    r.rent_pattern,
    case when r.rent_pattern = 'rent_change'
         then r.last_number else r.first_number end                    as unit_weekly_rent,
    case when r.rent_pattern = 'tenant_share'
         then r.second_number end                                      as tenant_weekly_share,
    case when r.rent_pattern = 'negotiable_range'
         then r.second_number end                                      as rent_range_high,
    b.rent_raw,
    v.visa_expiry_date
from base b
left join term_summary s using (source_file_sha256, source_row_number)
left join visa_dates   v using (source_file_sha256, source_row_number)
left join rent_kind    r using (source_file_sha256, source_row_number)
left join {{ ref('stg_address_parsed') }} a
       on a.src = 'tenant_list'
      and a.address_raw = b.address_raw
