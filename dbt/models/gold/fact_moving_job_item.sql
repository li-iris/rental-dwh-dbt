-- One row per (moving job, item type) with a recorded count. A zero means "checked, none".
select moving_job_id, item_code, item_name_as_written, quantity
from {{ ref('stg_moving_job_item') }}
