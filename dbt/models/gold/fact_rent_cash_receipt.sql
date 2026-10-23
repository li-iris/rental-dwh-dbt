-- One row per cash rent payment: collected from the tenant, handed in to the office, banked.
-- rent_month assumes the rent month is in the year the cash was collected.

select
    md5(c.source_file_sha256 || '|' || c.source_row_number::text || '|' || c.rent_month_number::text) as cash_receipt_id,
    p.property_id,
    c.address_raw,
    c.room_label,
    case when c.collected_date is not null
         then make_date(extract(year from c.collected_date)::int, c.rent_month_number, 1) end        as rent_month,
    c.cash_amount,
    nullif(initcap(btrim(c.collected_by_raw)), '')                   as collected_by,
    c.collected_date,
    c.handover_date,
    c.banked_date,
    nullif(initcap(btrim(c.banked_by_raw)), '')                      as banked_by,
    c.handover_date - c.collected_date                               as handover_gap_days,
    c.banked_date - c.handover_date                                  as bank_gap_days,
    c.banked_date - c.collected_date                                 as days_in_hand,
    c.handover_gap_days_written,
    c.bank_gap_days_written,
    c.note
from {{ ref('stg_rent_cash_receipt') }} c
left join {{ ref('stg_address_parsed') }} a
       on a.src = 'rent_cash' and a.address_raw = c.address_raw
left join {{ ref('dim_property') }} p
       on p.property_key = a.property_key
