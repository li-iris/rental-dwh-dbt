-- Every case must have exactly one row for every step. Fails if any combination is missing or doubled.
select actual_rows, expected_rows
from (
    select
        (select count(*) from {{ ref('fact_turnover_step') }})                                    as actual_rows,
        (select count(*) from {{ ref('fact_turnover_case') }})
          * (select count(*) from {{ ref('dim_turnover_step') }})                                 as expected_rows
) x
where actual_rows <> expected_rows
