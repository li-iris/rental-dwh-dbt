-- The sheet shows RMB amount, exchange rate, AUD amount, weekly rent, days paid, rent due and difference.
-- They must agree with each other (small rounding allowed). Fails if any row does not add up.
select rmb_receipt_id, address_raw, 'aud_amount differs from rmb_amount / exchange_rate' as problem
from {{ ref('fact_rmb_receipt') }}
where abs(rmb_amount / nullif(exchange_rate, 0) - aud_amount) > 1

union all
select rmb_receipt_id, address_raw, 'rent_due differs from weekly_rent * days_paid / 7'
from {{ ref('fact_rmb_receipt') }}
where abs(rent_due_aud - weekly_rent * days_paid / 7) > 0.05

union all
select rmb_receipt_id, address_raw, 'rent_difference differs from aud_amount - rent_due'
from {{ ref('fact_rmb_receipt') }}
where abs(aud_amount - rent_due_aud - rent_difference_aud) > 0.05
