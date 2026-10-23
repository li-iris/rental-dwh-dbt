-- One row per (turnover case x checklist step), INCLUDING steps nobody has recorded.
-- That is the point: a missing step shows up as a row with is_recorded = false, not as nothing.
--
-- Deadline of a step = the earlier of
--   (a) its own deadline: anchor date + offset  (anchor = move-in, move-out or lease end), and
--   (b) the day before the next tenant moves in, for steps flagged "must finish before next tenant".
-- Status is judged against report_date. By default that is the day dbt runs (current_date), so every
-- "overdue" figure is recalculated on each refresh. To look at the data as of an earlier day, override it:
--   dbt run --vars '{report_date: 2026-01-13}'

with report as (
    select report_date from {{ ref('dim_report_date') }}
),

grid as (
    select
        c.case_id, c.property_id, c.turnover_section, c.has_next_tenant,
        c.new_move_in_date, c.old_contract_end_date, c.move_out_date_used,
        s.step_code, s.step_order, s.stage, s.anchor, s.due_offset_days,
        s.before_next_move_in, s.rule_source
    from {{ ref('fact_turnover_case') }} c
    cross join {{ ref('dim_turnover_step') }} s
),

joined as (
    select
        g.*,
        (e.case_id is not null)         as is_recorded,
        coalesce(e.is_done, false)      as is_done,
        e.done_by,
        e.step_date,
        e.raw_text
    from grid g
    left join {{ ref('stg_turnover_step_entry') }} e
           on e.case_id = g.case_id
          and e.step_code = g.step_code
),

with_due as (
    select
        j.*,
        -- move-in steps only make sense when a new tenant is coming; listing steps not when the room is not re-let
        case
            when j.stage in ('move_in', 'booking') then j.has_next_tenant
            when j.stage = 'listing'               then j.turnover_section <> 'move_out_not_relisted'
            else true
        end as is_applicable,
        least(
            case j.anchor
                when 'move_in'   then j.new_move_in_date
                when 'move_out'  then j.move_out_date_used
                when 'lease_end' then coalesce(j.old_contract_end_date, j.move_out_date_used)
            end + j.due_offset_days,
            case when j.before_next_move_in and j.new_move_in_date is not null
                 then j.new_move_in_date - 1
            end
        ) as due_date
    from joined j
)

select
    w.case_id,
    w.step_code,
    w.property_id,
    w.is_applicable,
    w.is_recorded,
    w.is_done,
    w.done_by,
    w.step_date,
    w.due_date,
    w.rule_source,
    r.report_date,
    case
        when not w.is_applicable                                        then 'not_applicable'
        when w.is_done and w.due_date is not null
             and w.step_date is not null and w.step_date > w.due_date   then 'done_late'
        when w.is_done                                                  then 'done'
        when w.due_date is null                                         then 'no_deadline'
        when w.due_date < r.report_date                                 then 'overdue_not_done'
        when w.due_date <= r.report_date + 7                            then 'due_soon'
        else 'upcoming'
    end as status,
    case
        when w.is_done and w.step_date > w.due_date then w.step_date - w.due_date
        when not w.is_done and w.due_date < r.report_date then r.report_date - w.due_date
    end as days_late,
    w.raw_text
from with_due w
cross join report r
