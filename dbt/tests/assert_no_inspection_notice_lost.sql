-- Every inspection / notice in silver must be represented in gold (several silver rows may collapse into one when two workbook versions hold the same notice).
select s.notice_id, s.notice_type, s.address_raw, s.notice_date
from {{ ref('stg_inspection_notice') }} s
left join {{ ref('stg_address_parsed') }} a on a.src = 'inspection_list' and a.address_raw = s.address_raw
where not exists (
    select 1 from {{ ref('fact_inspection_notice') }} f
    where f.notice_type = s.notice_type
      and coalesce(f.property_key, lower(f.address_raw)) = coalesce(a.property_key, lower(s.address_raw))
      and f.notice_date is not distinct from s.notice_date
      and coalesce(f.category, '') = coalesce(s.category, '')
)
