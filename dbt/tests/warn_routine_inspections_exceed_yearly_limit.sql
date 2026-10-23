{{ config(severity='warn') }}
-- A property has more routine inspections in a rolling 12 months than the rule routine_inspection_max_per_year allows.
select n.property_id, n.notice_date as window_end, count(*) as inspections_in_12_months
from {{ ref('fact_inspection_notice') }} n
join {{ ref('fact_inspection_notice') }} w
  on w.property_id = n.property_id and w.notice_type = 'routine' and w.notice_date > n.notice_date - 365 and w.notice_date <= n.notice_date
where n.notice_type = 'routine' and n.property_id is not null and n.notice_date is not null
group by 1, 2
having count(*) > {{ rule('routine_inspection_max_per_year') }}
