-- Every water bill in silver must be represented in gold (two workbook versions may hold the same bill).
select s.water_bill_id, s.address_raw, s.period_text, s.amount
from {{ ref('stg_water_bill') }} s
left join {{ ref('stg_address_parsed') }} a on a.src = 'water_list' and a.address_raw = s.address_raw
where not exists (
    select 1 from {{ ref('fact_water_bill') }} f
    where coalesce(f.property_key, lower(f.address_raw)) = coalesce(a.property_key, lower(s.address_raw))
      and coalesce(f.period_text, '') = coalesce(s.period_text, '')
      and f.amount is not distinct from s.amount
)
