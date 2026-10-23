-- Every non-cancelled paperwork case must have exactly one row for every step of its process.
select c.case_id, c.process, count(f.step_code) as steps_found, (select count(*) from {{ ref('dim_process_step') }} s where s.process = c.process) as steps_expected
from {{ ref('fact_process_case') }} c
left join {{ ref('fact_process_step') }} f on f.case_id = c.case_id
where not c.is_cancelled
group by c.case_id, c.process
having count(f.step_code) <> (select count(*) from {{ ref('dim_process_step') }} s where s.process = c.process)
