{{ config(materialized='view') }}

-- One row per inspection / notice written in the sheet "查房通知". The sheet holds three blocks side by side:
--   routine = routine inspection (columns A-I), fire = fire safety inspection (M-R), other = other notices (U-AC).
-- Dates are written "2024.3.26", "2024 11.18" or "23/01/2024". sent_by is a staff name found in the "sent" cell.

with routine as (
    select 'routine' as notice_type, _source_file, _file_sha256, _row_number,
           trim(c_a) as address_raw, trim(c_b) as date_raw, trim(c_d) as time_text,
           trim(c_e) as email_text, trim(c_f) as message_text, trim(c_g) as pre_check_text,
           trim(c_h) as pre_check_by_text, trim(c_i) as attended_by_text,
           null::text as completion_text, null::text as category, null::text as notice_date_raw, null::text as follow_up_by
    from {{ source('bronze', 'inspection_notice') }}
    where _row_number > 2 and c_a ~ '^[0-9]'
),
fire as (
    select 'fire', _source_file, _file_sha256, _row_number,
           trim(c_m), trim(c_n), trim(c_p), trim(c_q), null, null, null, null,
           nullif(trim(c_r), ''), null, null, null
    from {{ source('bronze', 'inspection_notice') }}
    where _row_number > 2 and c_m ~ '^[0-9]'
),
other as (
    select 'other', _source_file, _file_sha256, _row_number,
           trim(c_u), trim(c_v), trim(c_x), trim(c_aa), null, null, null, null,
           nullif(trim(c_ac), ''), nullif(trim(c_y), ''), nullif(trim(c_z), ''), nullif(trim(c_ab), '')
    from {{ source('bronze', 'inspection_notice') }}
    where _row_number > 2 and c_u ~ '^[0-9]'
),
unioned as (
    select * from routine union all select * from fire union all select * from other
)

select
    md5(_file_sha256 || '|' || _row_number::text || '|' || notice_type) as notice_id,
    notice_type, _source_file as source_file, _row_number as source_row_number,
    address_raw,
    {{ first_date("regexp_replace(date_raw, '^(20[0-9]{2}) ', '\\1.')") }} as notice_date,
    date_raw,
    nullif(time_text, '')                                                as time_text,
    {{ first_date("regexp_replace(notice_date_raw, '^(20[0-9]{2}) ', '\\1.')") }} as notice_given_date,
    nullif(category, '')                                                 as category,
    (select sa.staff_name from regexp_matches(coalesce(email_text, ''), '[A-Za-z]+', 'g') t(m)
       join {{ ref('staff_aliases') }} sa on sa.alias = lower(t.m[1]) limit 1)  as sent_by,
    (email_text ~ '已发' or coalesce(message_text, '') ~ '已发')           as notice_sent,
    nullif(pre_check_text, '')                                           as pre_check_text,
    (select sa.staff_name from regexp_matches(coalesce(pre_check_by_text, ''), '[A-Za-z]+', 'g') t(m)
       join {{ ref('staff_aliases') }} sa on sa.alias = lower(t.m[1]) limit 1)  as pre_check_by,
    (select sa.staff_name from regexp_matches(coalesce(attended_by_text, ''), '[A-Za-z]+', 'g') t(m)
       join {{ ref('staff_aliases') }} sa on sa.alias = lower(t.m[1]) limit 1)  as attended_by,
    completion_text,
    (completion_text ~ '完成|done|已') as is_completed,
    follow_up_by
from unioned
