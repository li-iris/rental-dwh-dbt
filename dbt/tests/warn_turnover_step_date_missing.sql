{{ config(severity='warn') }}
-- Warning only: a step cell has a date but the year could not be worked out.
select case_id, step_code, raw_text
from {{ ref('stg_turnover_step_entry') }}
where entry_type = 'dated'
  and step_date is null
