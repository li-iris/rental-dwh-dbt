-- Fails if the same step of the same case appears twice.
select case_id, step_code, count(*) as rows_found
from {{ ref('stg_turnover_step_entry') }}
group by 1, 2
having count(*) > 1
