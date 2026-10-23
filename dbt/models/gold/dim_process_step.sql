-- One row per step column in the three paperwork checklists (new tenant, renewal, contract transfer).
-- Source of truth is the seed process_step_catalog.

select
    process,
    step_code,
    step_name,
    kind,
    row_number() over (partition by process order by length(column_letter), column_letter) as step_order
from {{ ref('process_step_catalog') }}
