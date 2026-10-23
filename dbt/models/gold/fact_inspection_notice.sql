-- One row per inspection / notice (routine, fire, other). Duplicates between workbook versions are removed,
-- keeping the version with the highest snapshot_rank.

with ranked as (
    select s.*, a.property_key, coalesce(o.snapshot_rank, 0) as snapshot_rank,
           row_number() over (
               partition by s.notice_type, coalesce(a.property_key, lower(s.address_raw)), s.notice_date, coalesce(s.category, '')
               order by coalesce(o.snapshot_rank, 0) desc, s.source_row_number
           ) as rn
    from {{ ref('stg_inspection_notice') }} s
    left join {{ ref('stg_address_parsed') }} a on a.src = 'inspection_list' and a.address_raw = s.address_raw
    left join {{ ref('source_snapshot_order') }} o on o.source_file = s.source_file
)
select
    r.notice_id, r.notice_type, p.property_id, r.property_key, r.address_raw,
    r.notice_date, r.time_text, r.notice_given_date, r.category,
    r.sent_by, r.notice_sent, r.pre_check_text, r.pre_check_by, r.attended_by,
    r.completion_text, r.is_completed, r.follow_up_by, r.source_file
from ranked r
left join {{ ref('dim_property') }} p on p.property_key = r.property_key
where r.rn = 1
