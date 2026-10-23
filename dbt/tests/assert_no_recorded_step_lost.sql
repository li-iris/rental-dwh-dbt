-- Every filled-in cell from the sheet must show up in gold as a recorded step.
select silver_rows, gold_rows
from (
    select
        (select count(*) from {{ ref('stg_turnover_step_entry') }})                    as silver_rows,
        (select count(*) from {{ ref('fact_turnover_step') }} where is_recorded)       as gold_rows
) x
where silver_rows <> gold_rows
