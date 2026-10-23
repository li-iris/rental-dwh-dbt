-- Water bills that still need action (everything not closed), with the property address.
select
    w.water_bill_id,
    coalesce(p.master_address_raw, w.address_raw) as property_address,
    w.period_text,
    w.amount,
    w.company_paid_date,
    w.invoice_status,
    w.follow_up_status,
    w.days_past_due,
    w.may_be_unrecoverable
from {{ ref('stg_water_bill') }} w
left join {{ ref('stg_property') }} p on p.property_id = w.property_id
where w.follow_up_status <> 'closed'
