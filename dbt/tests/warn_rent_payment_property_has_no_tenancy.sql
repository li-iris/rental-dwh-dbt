{{ config(severity='warn') }}
-- A rent payment was typed in for a property that has no lease covering the payment date.
select p.rent_payment_id, p.address_raw, p.paid_date, p.amount
from {{ ref('fact_rent_payment') }} p
where p.amount > 0
  and not exists (
      select 1 from {{ ref('dim_tenancy') }} t
      where t.property_id = p.property_id
        and (t.lease_start is null or t.lease_start <= p.paid_date)
        and (t.lease_end   is null or t.lease_end   >= p.paid_date - 30))
