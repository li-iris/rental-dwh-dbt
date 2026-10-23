-- One row per rent payment typed into entry.rent_payment (the Excel workbooks only had monthly totals, see fact_rent_roll_month).
-- A refund is a negative amount.
select
    md5('entry|' || e.rent_payment_id::text || '|rent')       as rent_payment_id,
    p.property_id,
    a.property_key,
    e.address                                                 as address_raw,
    e.paid_date,
    date_trunc('month', e.paid_date)::date                    as paid_month,
    e.amount,
    e.method,
    e.received_by,
    e.notes
from {{ source('entry', 'rent_payment') }} e
left join {{ ref('stg_address_parsed') }} a
       on a.src = 'entry_property' and a.address_raw = e.address
left join {{ ref('dim_property') }} p
       on p.property_key = a.property_key
