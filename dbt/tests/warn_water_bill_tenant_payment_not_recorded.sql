{{ config(severity='warn') }}
-- Business follow-up: an invoice was sent more than water_payment_due_days ago (seed business_rules) and no tenant payment is recorded
-- (and it was not settled in the exit report).
select address_raw, period_text, amount, invoice_text, days_past_due
from {{ ref('fact_water_bill') }}
where follow_up_status = 'payment_overdue'
