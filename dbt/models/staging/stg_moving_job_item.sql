{{ config(materialized='view') }}

-- Moving job items from the Excel workbooks plus items typed into entry.moving_job_item.

select * from {{ ref('stg_moving_job_item_excel') }}

union all

select
    md5('entry|' || i.moving_job_entry_id::text || '|moving') as moving_job_id,
    i.item_code,
    i.item_code                                                as item_name_as_written,
    i.quantity
from {{ source('entry', 'moving_job_item') }} i
