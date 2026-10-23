-- One row per RMB rent payment received. Amounts are kept as written in the sheet; the tests recompute them.

select
    md5(r.source_file_sha256 || '|' || r.source_row_number::text)   as rmb_receipt_id,
    p.property_id,
    r.address_raw,
    r.receipt_date,
    r.recorded_date,
    r.recorded_date - r.receipt_date                                 as days_to_record,
    nullif(initcap(btrim(r.recorded_by_raw)), '')                    as recorded_by,
    r.rmb_amount,
    r.exchange_rate,
    r.aud_amount,
    r.weekly_rent,
    r.days_paid,
    r.rent_due_aud,
    r.rent_difference_aud,
    case
        when r.detail ~ '首房租'   then 'first_rent'
        when r.detail ~ '预定金'   then 'booking_deposit_as_rent'
        else 'rent'
    end                                                              as payment_kind,
    r.detail
from {{ ref('stg_rmb_receipt') }} r
left join {{ ref('stg_address_parsed') }} a
       on a.src = 'rmb_receipts' and a.address_raw = r.address_raw
left join {{ ref('dim_property') }} p
       on p.property_key = a.property_key
