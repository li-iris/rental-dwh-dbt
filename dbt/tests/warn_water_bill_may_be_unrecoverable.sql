{{ config(severity='warn') }}
-- The agency paid the water bill more than water_invoice_legal_limit_days ago and no invoice is recorded:
-- under NSW rules the tenant may no longer have to pay it. Decide whether to bill it anyway or write it off.
select water_bill_id, address_raw, period_text, amount, company_paid_date, days_past_due
from {{ ref('fact_water_bill') }}
where may_be_unrecoverable
