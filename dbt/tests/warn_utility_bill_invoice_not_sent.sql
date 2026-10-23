{{ config(severity='warn') }}
-- Business follow-up: an electricity / gas bill has an amount but no invoice-sent note.
select address_raw, bill_type_raw, period_text, amount_text
from {{ ref('fact_utility_bill') }}
where amount is not null and not invoice_sent
