-- One row per moving job. job_date is only filled when the sheet gives a full date; "month.day" cells keep date_is_complete = false.
select
    j.moving_job_id, p.property_id, a.property_key, j.address_raw,
    j.job_date, j.date_raw, j.date_is_complete,
    j.rooms_text, j.bedrooms_first, j.stairs_text, j.work_time_text, j.work_hours_total,
    j.others_text, j.crew_text, j.start_text, j.end_text, j.note_text, j.problem_text,
    exists (select 1 from {{ ref('stg_moving_job_item') }} i where i.moving_job_id = j.moving_job_id) as has_item_counts,
    j.source_file
from {{ ref('stg_moving_job') }} j
left join {{ ref('stg_address_parsed') }} a on a.src = 'moving_list' and a.address_raw = j.address_raw
left join {{ ref('dim_property') }} p on p.property_key = a.property_key
