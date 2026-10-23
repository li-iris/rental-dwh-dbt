-- One row per special clause. A clause with no status text means nobody has recorded that it was carried out.
with ranked as (
    select s.*, a.property_key,
           row_number() over (partition by coalesce(a.property_key, lower(s.address_raw)), s.term_text
                              order by coalesce(o.snapshot_rank, 0) desc, s.source_row_number) as rn
    from {{ ref('stg_special_term') }} s
    left join {{ ref('stg_address_parsed') }} a on a.src = 'special_terms' and a.address_raw = s.address_raw
    left join {{ ref('source_snapshot_order') }} o on o.source_file = s.source_file
)
select r.special_term_id, p.property_id, r.property_key, r.address_raw, r.term_text, r.status_text,
       r.has_status, r.recorded_by, r.recorded_text, r.amount_symbol, r.amount_text, r.source_file
from ranked r
left join {{ ref('dim_property') }} p on p.property_key = r.property_key
where r.rn = 1
