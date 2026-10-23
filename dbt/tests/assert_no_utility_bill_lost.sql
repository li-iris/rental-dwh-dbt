-- Every electricity / gas line in silver must be represented in gold.
select s.utility_bill_id, s.address_raw, s.bill_type_raw, s.period_text
from {{ ref('stg_utility_bill') }} s
left join {{ ref('stg_address_parsed') }} a on a.src = 'utility_list' and a.address_raw = s.address_raw
where not exists (
    select 1 from {{ ref('fact_utility_bill') }} f
    where coalesce(f.property_key, lower(f.address_raw)) = coalesce(a.property_key, lower(s.address_raw))
      and coalesce(f.bill_type_raw, '') = coalesce(s.bill_type_raw, '')
      and coalesce(f.period_text, '') = coalesce(s.period_text, '')
      and coalesce(f.amount_text, '') = coalesce(s.amount_text, '')
)
