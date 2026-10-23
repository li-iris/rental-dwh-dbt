-- Anything written in a step cell must reach gold (for cases kept after removing duplicates between workbook versions).
select e.case_id, e.step_code, e.raw_text
from {{ ref('stg_process_step_entry') }} e
join {{ ref('fact_process_case') }} c on c.case_id = e.case_id
left join {{ ref('fact_process_step') }} f on f.case_id = e.case_id and f.step_code = e.step_code and f.raw_text = e.raw_text
where f.case_id is null
