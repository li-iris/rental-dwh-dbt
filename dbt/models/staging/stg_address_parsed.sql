{{ config(materialized='table') }}

-- Parses every distinct raw address into unit / street number / street / room,
-- and builds property_key = [unit/]street_number street  (no suburb, no postcode).
-- Properties are the union of all sheets.

with addresses as (
    select 'reconciliation' as src, trim(c_a) as address_raw
    from {{ source('bronze', 'rent_reconciliation') }} where _row_number > 1 and c_a is not null
    union
    select 'rent_credit', trim(c_b)
    from {{ source('bronze', 'rent_credit') }} where _row_number > 2 and c_b is not null
    union
    select 'rmb_receipts', trim(c_a)
    from {{ source('bronze', 'rmb_receipts') }} where _row_number > 1 and c_a is not null
    union
    select 'profit', trim(c_a)
    from {{ source('bronze', 'profit_monthly') }} where _row_number > 1 and c_a is not null
    union
    select 'tenant_list', trim(c_a)
    from {{ source('bronze', 'tenant_list') }}
    where _row_number > 1 and c_a is not null and c_c is not null
    union
    -- this sheet has section title rows (e.g. "1.xxx") between the data rows
    select 'tenancy_lifecycle', trim(c_a)
    from {{ source('bronze', 'tenancy_lifecycle') }}
    where _row_number > 4 and c_a ~ '^[0-9]' and c_a !~ '^[0-9]+\s*[.、]'
    union
    select src, address_raw
    from {{ ref('stg_address_sources_extra') }}
),

cleaned as (
    select src, address_raw,
        regexp_replace(
          regexp_replace(
            regexp_replace(
              regexp_replace(
                regexp_replace(
                  regexp_replace(
                    lower(trim(translate(address_raw, E'\u00a0\u3000\u2003', '   '))),
                    '[（(].*$', ''),                       -- drop trailing notes in brackets
                  '，', ',', 'g'),                          -- full-width comma
                '([0-9])([a-z]{3,})', '\1 \2', 'g'),        -- "41Marlow" -> "41 Marlow"
              '\s*/\s*', '/', 'g'),                         -- "84 / 255" -> "84/255"
            '\s+', ' ', 'g'),
          '^([0-9]+[a-z]?) ([0-9]+[a-z]? [a-z])', '\1/\2')  -- "4 4 Marlow" -> "4/4 Marlow"
        as c
    from addresses
),

split as (
    select src, address_raw,
        m[1] as unit_raw,
        m[2] as street_number,
        substring(m[3] from '^\s*([a-z]+)') as street_token_raw,
        regexp_replace(m[3], '^\s*[a-z]+', '') as rest
    from (
        select src, address_raw,
               regexp_match(c, '^(?:([0-9a-z]+)/)?([0-9]+[a-z]?)(?:-[0-9]+[a-z]?)?(.*)$') as m
        from cleaned
    ) t
),

parsed as (
    select
        s.src, s.address_raw,
        -- "E206" and "206E" are the same unit: always write digits first
        case when s.unit_raw ~ '^[a-z]+[0-9]+$'
             then substring(s.unit_raw from '[0-9]+') || substring(s.unit_raw from '^[a-z]+')
             else s.unit_raw end as unit,
        s.street_number,
        coalesce(f.correct_token, s.street_token_raw) as street_token,
        -- what is left after removing street type and suburb = the room name
        nullif(btrim(
            regexp_replace(
              regexp_replace(
                regexp_replace(
                  regexp_replace(s.rest,
                    '^[\s,]*(street|st|road|rd|avenue|ave|parade|pde)\M', ''),
                  '\m(sampletown|nsw|203[0-9])\M', '', 'g'),
                '[\s,.\-_]+', ' ', 'g'),
              'room (\d)', 'room\1', 'g')
        ), '') as room_label
    from split s
    left join {{ ref('street_token_fixes') }} f on f.wrong_token = s.street_token_raw
),

-- addresses written without a street name (e.g. "11/113") are resolved
-- only when exactly one property with that unit/number exists
master_keys as (
    select distinct unit, street_number,
           coalesce(unit || '/', '') || street_number || ' ' || street_token as property_key
    from parsed
    where street_token is not null
),
unique_master as (
    select unit, street_number, min(property_key) as property_key
    from master_keys
    group by unit, street_number
    having count(*) = 1
)

select
    p.src,
    p.address_raw,
    p.unit,
    p.street_number,
    p.street_token,
    p.room_label,
    case
        when p.street_token is null and u.property_key is not null then u.property_key
        else coalesce(p.unit || '/', '') || p.street_number || ' ' || coalesce(p.street_token, '')
    end as property_key
from parsed p
left join unique_master u
       on u.unit is not distinct from p.unit
      and u.street_number = p.street_number
