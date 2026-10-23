-- The owner's checklist: applicable steps that are overdue or due within 7 days of report_date.
-- rule_source tells how much to trust the deadline: 'default_to_confirm' = placeholder awaiting the owner.

select
    c.address_raw,
    c.property_key,
    c.turnover_section,
    c.old_contract_end_date,
    c.actual_move_out_date,
    c.new_move_in_date,
    s.step_order,
    s.stage,
    s.step_name,
    f.due_date,
    f.status,
    f.days_late,
    f.rule_source,
    f.report_date,
    c.case_id,
    s.step_code
from {{ ref('fact_turnover_step') }} f
join {{ ref('fact_turnover_case') }} c using (case_id)
join {{ ref('dim_turnover_step') }} s using (step_code)
where f.status in ('overdue_not_done', 'due_soon')
order by c.property_key, c.case_id, s.step_order
