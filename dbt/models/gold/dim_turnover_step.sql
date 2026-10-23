-- One row per step in the move-in / move-out checklist, with its deadline rule.
-- Source of truth is the seed turnover_step_catalog (edit the CSV, not this SQL, when the owner changes a rule).

select
    step_code,
    step_name,
    stage,
    anchor,
    due_offset_days,
    before_next_move_in,
    rule_source,
    row_number() over (order by length(column_letter), column_letter) as step_order
from {{ ref('turnover_step_catalog') }}
