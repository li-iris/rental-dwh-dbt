select
    water_bill_id,
    property_id,
    address_raw,
    period_text,
    period_start,
    period_end,
    amount,
    company_paid_date,
    invoice_sent_date,
    tenant_paid_date,
    settled_in_exit_report,
    invoice_status,
    follow_up_status,
    days_past_due,
    may_be_unrecoverable
from {{ source('raw', 'fact_water_bill') }}
