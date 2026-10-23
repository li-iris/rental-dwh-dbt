-- One row per (case, step): the full grid, so a step nobody recorded shows up as "no record"
-- instead of silently not existing. This is the "no omissions" view for the paperwork checklists.

select
    c.case_id,
    c.process,
    s.step_code,
    s.step_order,
    e.raw_text,
    coalesce(e.entry_type, 'no_record')                   as entry_type,
    coalesce(e.is_done, false)                            as is_done,
    (e.case_id is null)                                   as is_missing,
    e.done_by,
    e.step_date,
    coalesce(e.year_was_inferred, false)                  as year_was_inferred,
    e.decision
from {{ ref('fact_process_case') }} c
join {{ ref('dim_process_step') }} s on s.process = c.process
left join {{ ref('stg_process_step_entry') }} e
       on e.case_id = c.case_id and e.step_code = s.step_code
where not c.is_cancelled
union all
-- cancelled cases keep only what was recorded
select c.case_id, c.process, s.step_code, s.step_order, e.raw_text, e.entry_type, e.is_done, false,
       e.done_by, e.step_date, e.year_was_inferred, e.decision
from {{ ref('fact_process_case') }} c
join {{ ref('stg_process_step_entry') }} e on e.case_id = c.case_id
join {{ ref('dim_process_step') }} s on s.process = c.process and s.step_code = e.step_code
where c.is_cancelled
