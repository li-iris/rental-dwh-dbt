{{ config(materialized='view') }}

-- Moving jobs from the Excel workbooks plus jobs typed into entry.moving_job.

select * from {{ ref('stg_moving_job_excel') }}

union all

select
    md5('entry|' || e.moving_job_entry_id::text || '|moving')  as moving_job_id,
    'entry'::text                                              as source_file,
    'entry'::text                                              as source_file_sha256,
    e.moving_job_entry_id::int                                 as source_row_number,
    e.address                                                  as address_raw,
    e.job_date::text                                           as date_raw,
    e.job_date,
    false                                                      as date_is_month_day_only,
    true                                                       as date_is_complete,
    e.rooms_text,
    e.bedrooms                                                 as bedrooms_first,
    e.stairs_text,
    null::text                                                 as work_time_text,
    e.work_hours                                               as work_hours_total,
    null::text                                                 as others_text,
    e.crew_text,
    null::text                                                 as start_text,
    null::text                                                 as end_text,
    e.note_text,
    e.problem_text
from {{ source('entry', 'moving_job') }} e
