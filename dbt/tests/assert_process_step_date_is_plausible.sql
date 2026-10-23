-- A step date outside 2023-2027 almost certainly means a typo or a wrongly guessed year.
select case_id, step_code, raw_text, step_date
from {{ ref('fact_process_step') }}
where step_date < date '2023-01-01' or step_date > date '2027-12-31'
