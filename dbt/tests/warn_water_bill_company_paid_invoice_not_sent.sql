{{ config(severity='warn') }}
-- Business follow-up: the company paid this water bill more than water_invoice_due_days ago (seed business_rules) and no invoice
-- to the tenant is recorded (and it was not settled in the exit report), so the money may never be collected.
select address_raw, period_text, amount, company_paid_text, days_past_due
from {{ ref('fact_water_bill') }}
where follow_up_status = 'invoice_overdue'
