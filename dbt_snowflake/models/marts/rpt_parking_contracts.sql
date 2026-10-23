-- Parking and garage contracts with the property address and how many days ago the written end date passed
-- (negative = still in the future), judged against the report date of the local warehouse.
select
    l.parking_lease_id,
    coalesce(p.master_address_raw, l.address_raw) as property_address,
    l.space_kind,
    l.contract_status,
    l.contract_end_date,
    case when l.contract_end_date is not null
         then datediff('day', l.contract_end_date, r.report_date) end as days_since_end_date
from {{ ref('stg_parking_lease') }} l
left join {{ ref('stg_property') }} p on p.property_id = l.property_id
cross join {{ ref('stg_report_date') }} r
