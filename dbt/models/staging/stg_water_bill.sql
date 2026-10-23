{{ config(materialized='view') }}

-- Water bills from the Excel workbooks (stg_water_bill_excel) plus bills typed into entry.water_bill.

select * from {{ ref('stg_water_bill_excel') }}

union all

select
    md5('entry|' || e.water_bill_entry_id::text || '|water')                     as water_bill_id,
    'entry'::text                                                                as source_file,
    e.water_bill_entry_id::int                                                   as source_row_number,
    e.address                                                                    as address_raw,
    case when e.period_start is not null or e.period_end is not null
         then coalesce(e.period_start::text, '?') || ' - ' || coalesce(e.period_end::text, '?') end as period_text,
    e.period_start,
    e.period_end,
    e.amount,
    case when e.has_water_bill_copy then 'yes' end                               as water_bill_copy_text,
    e.has_water_bill_copy,
    e.company_paid_date,
    e.company_paid_date::text                                                    as company_paid_text,
    case when e.settled_in_exit_report then 'settled in exit report'
         when e.invoice_sent_date is not null
         then e.invoice_sent_date::text || coalesce(' ' || e.invoice_sent_by, '') end as invoice_text,
    e.invoice_sent_date,
    e.settled_in_exit_report,
    e.invoice_sent_by,
    e.tenant_paid_date::text                                                     as tenant_paid_text,
    e.tenant_paid_date,
    null::text                                                                   as checked_text
from {{ source('entry', 'water_bill') }} e
