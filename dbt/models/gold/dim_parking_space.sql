-- Parking and garage price list by building: price per month or per week, bond, access and cover type.
-- The newest workbook version of each row is kept.

with ranked as (
    select
        s.*,
        row_number() over (
            partition by s.address_raw, s.source_list
            order by o.snapshot_rank desc, s.source_row_number desc
        ) as version_rank
    from {{ ref('stg_parking_space') }} s
    join {{ ref('source_snapshot_order') }} o on o.source_file = s.source_file
)

select
    md5(address_raw || '|' || source_list)   as parking_space_id,
    address_raw,
    price_period,
    price,
    bond,
    access_type_raw   as access_type,
    cover_type_raw    as cover_type,
    source_file
from ranked
where version_rank = 1
