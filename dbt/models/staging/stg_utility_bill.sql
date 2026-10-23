{{ config(materialized='view') }}

-- Electricity / gas bills from the Excel workbooks plus bills typed into entry.utility_bill.

select * from {{ ref('stg_utility_bill_excel') }}

union all

select
    md5('entry|' || e.utility_bill_entry_id::text || '|utility')                 as utility_bill_id,
    'entry'::text                                                                as source_file,
    e.utility_bill_entry_id::int                                                 as source_row_number,
    e.address                                                                    as address_raw,
    e.bill_type                                                                  as bill_type_raw,
    e.bill_type,
    case when e.period_start is not null or e.period_end is not null
         then coalesce(e.period_start::text, '?') || ' - ' || coalesce(e.period_end::text, '?') end as period_text,
    e.period_start,
    e.period_end,
    e.due_date,
    e.amount,
    false                                                                        as amount_has_note,
    e.amount::text                                                               as amount_text,
    null::text                                                                   as calc_file_text,
    case when e.invoice_sent_date is not null
         then e.invoice_sent_date::text || coalesce(' ' || e.invoice_sent_by, '') end as invoice_text,
    e.invoice_sent_date,
    e.invoice_sent_by,
    e.payment_check_date::text                                                   as payment_check_text,
    e.payment_check_date,
    e.is_not_set_up
from {{ source('entry', 'utility_bill') }} e
