-- One row per parking space or garage listed with a contract status. Where the space sits in a property we
-- manage, property_id is filled; otherwise it is empty. The newest workbook version of each row is kept.
-- contract_end_date is the date written beside the space (assumed to be the contract end date).

with ranked as (
    select
        l.*,
        row_number() over (
            partition by l.address_raw, l.source_list
            order by o.snapshot_rank desc, l.source_row_number desc
        ) as version_rank
    from {{ ref('stg_parking_lease') }} l
    join {{ ref('source_snapshot_order') }} o on o.source_file = l.source_file
)

select
    md5(r.address_raw || '|' || r.source_list)       as parking_lease_id,
    p.property_id,
    r.address_raw,
    r.address_standard,
    r.space_kind,
    r.source_list,
    r.lease_status,
    r.contract_end_date,
    -- rule: a dated contract whose end date is before the report date is treated as expired (renewals must be written into the sheet)
    case
        when r.lease_status = 'dated' and r.contract_end_date < (select report_date from {{ ref('dim_report_date') }}) then 'expired_by_date'
        when r.lease_status = 'dated' then 'active'
        else r.lease_status
    end as contract_status,
    r.source_file
from ranked r
left join {{ ref('stg_address_parsed') }} a
       on a.src = 'parking_lease' and a.address_raw = r.address_standard
left join {{ ref('dim_property') }} p
       on p.property_key = a.property_key
where r.version_rank = 1
