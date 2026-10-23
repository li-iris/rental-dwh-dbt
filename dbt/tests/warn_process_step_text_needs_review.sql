{{ config(severity='warn') }}
-- Business follow-up: free text in a step cell that is neither a date nor a clear yes/no. Someone should confirm if the step is done.
select case_id, process, step_code, raw_text
from {{ ref('fact_process_step') }}
where entry_type = 'text_only'
