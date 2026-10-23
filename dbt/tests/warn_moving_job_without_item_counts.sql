{{ config(severity='warn') }}
-- Business follow-up: no item counts were written for this moving job.
select address_raw, date_raw
from {{ ref('fact_moving_job') }}
where not has_item_counts
