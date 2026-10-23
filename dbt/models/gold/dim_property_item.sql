-- One row per item the company bought for a property. The same item appears in several workbook versions;
-- the version from the newest workbook (seed source_snapshot_order) is kept.

with ranked as (
    select
        i.*,
        row_number() over (
            partition by i.address_raw, i.item_name, i.installed_raw
            order by o.snapshot_rank desc, i.source_row_number desc
        ) as version_rank
    from {{ ref('stg_property_item') }} i
    join {{ ref('source_snapshot_order') }} o on o.source_file = i.source_file
)

select
    md5(r.address_raw || '|' || r.item_name || '|' || r.installed_raw)  as property_item_id,
    p.property_id,
    r.address_raw,
    r.item_name,
    case
        when r.condition_raw ~ '非全新'   then 'used'
        when r.condition_raw ~ '基本全新' then 'almost_new'
        when r.condition_raw ~ '全新'     then 'new'
        else r.condition_raw
    end                                                                  as condition,
    r.price,
    r.installed_raw,
    r.installed_date,
    r.installed_date_precision,
    r.removed_note,
    (r.removed_note is not null)                                         as has_removal_note,
    r.source_file
from ranked r
left join {{ ref('stg_address_parsed') }} a
       on a.src = 'property_items' and a.address_raw = r.address_raw
left join {{ ref('dim_property') }} p
       on p.property_key = a.property_key
where r.version_rank = 1
