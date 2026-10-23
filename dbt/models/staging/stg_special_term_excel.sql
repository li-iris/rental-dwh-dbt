{{ config(materialized='view') }}

-- One row per special clause agreed with a tenant (sheet "特别条款"): address, the clause, how it was carried out, who recorded it.
-- The "recorded" cell is "month.day Name"; the year is not written, so only the name is kept as a field and the text is kept as written.

select
    md5(_file_sha256 || '|' || _row_number::text || '|special_term') as special_term_id,
    _source_file       as source_file,
    _row_number        as source_row_number,
    trim(c_a)          as address_raw,
    trim(c_b)          as term_text,
    nullif(trim(c_c), '') as status_text,
    nullif(trim(c_d), '') as recorded_text,
    (select sa.staff_name from regexp_matches(coalesce(c_d, ''), '[A-Za-z]+', 'g') t(m)
       join {{ ref('staff_aliases') }} sa on sa.alias = lower(t.m[1]) limit 1) as recorded_by,
    nullif(trim(c_c), '') is not null as has_status,
    -- amounts mentioned in the term or status, e.g. ￥13464.3 or $4207.14
    (regexp_match(coalesce(c_b, '') || ' ' || coalesce(c_c, ''), '([￥¥$])\s*([0-9][0-9,]*(?:\.[0-9]+)?)'))[1] as amount_symbol,
    ((regexp_match(coalesce(c_b, '') || ' ' || coalesce(c_c, ''), '([￥¥$])\s*([0-9][0-9,]*(?:\.[0-9]+)?)'))[2]) as amount_text
from {{ source('bronze', 'special_terms') }}
where _row_number > 1 and c_a ~ '^[0-9]' and nullif(trim(c_b), '') is not null
