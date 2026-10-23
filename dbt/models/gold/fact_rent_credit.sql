-- One row per rent credit given to a tenant for vacant rent (a cost for the company).
select
    md5(c.source_file_sha256 || '|' || c.source_row_number::text)   as credit_id,
    md5(a.property_key)                                              as property_id,
    c.start_date,
    c.end_date,
    c.days,
    c.weekly_rent,
    c.credit_amount,
    c.booked_amount,
    c.booked_amount - c.credit_amount                                as booked_difference,
    c.note                                                           as note_raw,
    c.booked_by,
    c.booked_date
from {{ ref('stg_rent_credit') }} c
join {{ ref('stg_address_parsed') }} a
  on a.src = 'rent_credit'
 and a.address_raw = c.address_raw
