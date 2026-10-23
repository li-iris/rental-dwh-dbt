{{ config(materialized='view') }}

-- One row per (moving job, item type) with a count. Item names come from the English header row of the sheet.
-- A blank cell is not a row; a 0 is kept (the item was checked and there were none).

with header as (
    select _file_sha256, to_jsonb(h) as hj
    from {{ source('bronze', 'moving_jobs') }} h
    where _row_number = 1
)

select
    j.moving_job_id,
    case lower(trim(hk.v))
        when 'microvave' then 'microwave'
        else regexp_replace(lower(trim(hk.v)), '[^a-z0-9]+', '_', 'g')
    end as item_code,
    trim(hk.v) as item_name_as_written,
    kv.v::numeric as quantity
from {{ ref('stg_moving_job') }} j
join {{ source('bronze', 'moving_jobs') }} t
  on t._file_sha256 = j.source_file_sha256 and t._row_number = j.source_row_number
join header h on h._file_sha256 = j.source_file_sha256
cross join lateral jsonb_each_text(to_jsonb(t)) as kv(k, v)
join lateral (select h.hj ->> kv.k as v) hk on true
where kv.k in ('c_i','c_j','c_k','c_l','c_m','c_n','c_o','c_p','c_q','c_r','c_s','c_t','c_u','c_v')
  and kv.v ~ '^[0-9]+(\.[0-9]+)?$'
  and hk.v is not null
