select case_id, step_code, count(*) as rows_found
from {{ ref('fact_turnover_step') }}
group by 1, 2
having count(*) > 1
