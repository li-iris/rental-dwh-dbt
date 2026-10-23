-- Every moving job row in silver must reach gold, and every item count must belong to a job in gold.
select j.moving_job_id, 'job missing in gold' as problem
from {{ ref('stg_moving_job') }} j
left join {{ ref('fact_moving_job') }} f on f.moving_job_id = j.moving_job_id
where f.moving_job_id is null
union all
select i.moving_job_id, 'item count missing in gold'
from {{ ref('stg_moving_job_item') }} i
left join {{ ref('fact_moving_job_item') }} f on f.moving_job_id = i.moving_job_id and f.item_code = i.item_code
where f.moving_job_id is null
