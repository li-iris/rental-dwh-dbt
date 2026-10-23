{{ config(materialized='view') }}

-- One row per case in the three paperwork checklists:
--   rental_application = new-tenant paperwork (sheet "2.办理租房手续list")
--   rent_review        = lease renewal         (sheet "4.办理续租Rental review list")
--   contract_transfer  = sublet / contract change (sheet "3.转合同-变更信息表格")
-- Tenant names, phone numbers and e-mail addresses in these sheets are deliberately not carried into silver.
-- anchor_date is the date used to work out the missing year of "month.day" cells in the step columns.

with application as (
    select
        md5(_file_sha256 || '|' || _row_number::text || '|rental_application')   as case_id,
        'rental_application'                                                      as process,
        _source_file as source_file, _file_sha256 as source_file_sha256, _row_number as source_row_number,
        trim(c_a)                                                                 as address_raw,
        nullif(trim(c_b), '')                                                     as case_type_raw,
        {{ first_date('c_g') }}                                                   as contract_end_date,
        null::date                                                                as move_out_date,
        null::date                                                                as move_in_date,
        null::numeric                                                             as old_rent,
        null::numeric                                                             as new_rent,
        nullif(trim(c_l), '')                                                     as bills_note
    from {{ source('bronze', 'rental_application') }}
    where _row_number > 1 and c_a ~ '^[0-9]'
),

review as (
    select
        md5(_file_sha256 || '|' || _row_number::text || '|rent_review'),
        'rent_review',
        _source_file, _file_sha256, _row_number,
        trim(c_a),
        nullif(trim(c_b), ''),
        {{ first_date('c_d') }},
        {{ first_date('c_e') }},
        null::date,
        {{ to_num('c_f') }},
        {{ to_num('c_g') }},
        null::text
    from {{ source('bronze', 'rent_review') }}
    where _row_number > 1 and c_a ~ '^[0-9]'
),

transfer as (
    select
        md5(_file_sha256 || '|' || _row_number::text || '|contract_transfer'),
        'contract_transfer',
        _source_file, _file_sha256, _row_number,
        trim(c_a),
        nullif(trim(c_h), ''),
        null::date,
        {{ first_date('c_c') }},
        {{ first_date('c_g') }},
        null::numeric,
        null::numeric,
        null::text
    from {{ source('bronze', 'contract_transfer') }}
    where _row_number > 1 and c_a ~ '^[0-9]'
),

unioned as (
    select * from application
    union all select * from review
    union all select * from transfer
)

select
    u.*,
    case
        when u.case_type_raw ~ '短租'   then 'short_term'
        when u.case_type_raw ~ '长租'   then 'long_term'
        when u.case_type_raw ~ '转租'   then 'sublet'
        when u.case_type_raw ~ '续租'   then 'renewal'
        else null
    end                                                                           as case_type,
    (u.address_raw ~ '不租了|不转了')                                               as is_cancelled,
    case u.process
        when 'rental_application' then u.contract_end_date
        when 'rent_review'        then u.contract_end_date
        else coalesce(u.move_in_date, u.move_out_date)
    end                                                                           as anchor_date
from unioned u
