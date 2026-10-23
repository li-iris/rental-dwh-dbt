{{ config(materialized='view') }}

-- Inspections and notices from the Excel workbooks plus rows typed into entry.inspection_notice.

select * from {{ ref('stg_inspection_notice_excel') }}

union all

select
    md5('entry|' || e.inspection_entry_id::text || '|notice')   as notice_id,
    e.notice_type,
    'entry'::text                                                as source_file,
    e.inspection_entry_id::int                                   as source_row_number,
    e.address                                                    as address_raw,
    e.notice_date,
    e.notice_date::text                                          as date_raw,
    e.time_text,
    e.notice_given_date,
    e.category,
    e.sent_by,
    e.notice_sent,
    null::text                                                   as pre_check_text,
    e.pre_check_by,
    e.attended_by,
    e.completion_text,
    e.is_completed,
    e.follow_up_by
from {{ source('entry', 'inspection_notice') }} e
