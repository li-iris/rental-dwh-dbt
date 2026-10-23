{{ config(severity='warn') }}
-- Business follow-up: the step is marked done but no date was written, so lateness cannot be judged.
select case_id, process, step_code, raw_text
from {{ ref('fact_process_step') }}
where is_done and step_date is null and entry_type in ('text_done', 'yes', 'name_only')
