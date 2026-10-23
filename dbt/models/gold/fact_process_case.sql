-- One row per paperwork case (a row in the new-tenant, renewal or contract-transfer sheet).
-- The same case can appear in both workbook versions; only the row from the preferred version
-- (highest snapshot_rank in seed source_snapshot_order) is kept.

with ranked as (
    select
        c.*,
        a.property_key,
        o.snapshot_rank,
        row_number() over (
            partition by c.process, a.property_key, c.anchor_date, c.case_type_raw
            order by coalesce(o.snapshot_rank, 0) desc, c.source_row_number
        ) as rn
    from {{ ref('stg_process_case') }} c
    left join {{ ref('stg_address_parsed') }} a
           on a.src = 'process_list' and a.address_raw = c.address_raw
    left join {{ ref('source_snapshot_order') }} o on o.source_file = c.source_file
)

select
    r.case_id,
    r.process,
    p.property_id,
    r.property_key,
    r.address_raw,
    r.case_type,
    r.is_cancelled,
    r.anchor_date,
    r.contract_end_date,
    r.move_out_date,
    r.move_in_date,
    r.old_rent,
    r.new_rent,
    case when r.old_rent > 0 and r.new_rent is not null
         then round((r.new_rent - r.old_rent) / r.old_rent * 100, 1) end as rent_change_pct,
    r.source_file
from ranked r
left join {{ ref('dim_property') }} p on p.property_key = r.property_key
where r.rn = 1
