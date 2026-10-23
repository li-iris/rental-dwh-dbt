-- One row per water bill (property x billing period). The same bill can be in both workbook versions;
-- only the row from the preferred version (highest snapshot_rank) is kept.

with ranked as (
    select s.*, a.property_key, coalesce(o.snapshot_rank, 0) as snapshot_rank,
           row_number() over (
               partition by coalesce(a.property_key, lower(s.address_raw)), coalesce(s.period_text, ''), s.amount
               order by coalesce(o.snapshot_rank, 0) desc, s.source_row_number
           ) as rn
    from {{ ref('stg_water_bill') }} s
    left join {{ ref('stg_address_parsed') }} a on a.src = 'water_list' and a.address_raw = s.address_raw
    left join {{ ref('source_snapshot_order') }} o on o.source_file = s.source_file
)
select
    r.water_bill_id, p.property_id, r.property_key, r.address_raw,
    r.period_text, r.period_start, r.period_end, r.amount,
    r.has_water_bill_copy, r.company_paid_date, r.company_paid_text,
    r.invoice_sent_date, r.invoice_sent_by, r.invoice_text, r.settled_in_exit_report,
    case when r.settled_in_exit_report then 'settled_in_exit_report'
         when r.invoice_text is not null then 'invoice_sent'
         else 'invoice_not_sent' end as invoice_status,
    r.tenant_paid_date, r.tenant_paid_text, (r.tenant_paid_text is not null) as tenant_payment_recorded,
    r.checked_text,
    -- follow-up status, judged against the report date (the day dbt runs unless --vars report_date is set) using the rules in seed business_rules:
    --   invoice should go out within water_invoice_due_days after the company paid; tenant should pay within water_payment_due_days after the invoice
    case
        when r.settled_in_exit_report or r.tenant_paid_text is not null then 'closed'
        when r.invoice_text is null and r.company_paid_date is null     then 'company_not_paid_yet'
        when r.invoice_text is null and r.company_paid_date + {{ rule_days('water_invoice_due_days') }} < rd.report_date then 'invoice_overdue'
        when r.invoice_text is null                                     then 'invoice_due_soon'
        when coalesce(r.invoice_sent_date, r.company_paid_date) is null then 'payment_date_unknown'
        when coalesce(r.invoice_sent_date, r.company_paid_date) + {{ rule_days('water_payment_due_days') }} < rd.report_date then 'payment_overdue'
        else 'awaiting_payment'
    end as follow_up_status,
    case
        when r.settled_in_exit_report or r.tenant_paid_text is not null then null
        when r.invoice_text is null and r.company_paid_date is not null
            then rd.report_date - (r.company_paid_date + {{ rule_days('water_invoice_due_days') }})
        when r.invoice_text is not null and coalesce(r.invoice_sent_date, r.company_paid_date) is not null
            then rd.report_date - (coalesce(r.invoice_sent_date, r.company_paid_date) + {{ rule_days('water_payment_due_days') }})
    end as days_past_due,
    -- NSW lets an agent charge water usage only if the tenant is asked within 3 months of the bill being issued.
    -- The issue date is not in the lists, so the day the agency paid it is used (rule water_invoice_legal_limit_days).
    coalesce(r.invoice_text is null and r.company_paid_date is not null
        and not coalesce(r.settled_in_exit_report, false) and r.tenant_paid_text is null
        and r.company_paid_date + {{ rule_days('water_invoice_legal_limit_days') }} < rd.report_date, false) as may_be_unrecoverable,
    r.source_file
from ranked r
cross join (select report_date from {{ ref('dim_report_date') }}) rd
left join {{ ref('dim_property') }} p on p.property_key = r.property_key
where r.rn = 1
