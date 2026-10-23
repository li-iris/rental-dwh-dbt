-- One row per electricity / gas bill line. Rows with no amount and no period are bills that have not been set up yet.
with ranked as (
    select s.*, a.property_key,
           row_number() over (
               partition by coalesce(a.property_key, lower(s.address_raw)), coalesce(s.bill_type_raw, ''), coalesce(s.period_text, ''), coalesce(s.amount_text, '')
               order by coalesce(o.snapshot_rank, 0) desc, s.source_row_number
           ) as rn
    from {{ ref('stg_utility_bill') }} s
    left join {{ ref('stg_address_parsed') }} a on a.src = 'utility_list' and a.address_raw = s.address_raw
    left join {{ ref('source_snapshot_order') }} o on o.source_file = s.source_file
)
select
    r.utility_bill_id, p.property_id, r.property_key, r.address_raw,
    r.bill_type, r.bill_type_raw, r.period_text, r.period_start, r.period_end, r.due_date,
    r.amount, r.amount_has_note, r.amount_text, r.calc_file_text,
    r.invoice_text, r.invoice_sent_date, r.invoice_sent_by,
    r.payment_check_text, r.payment_check_date,
    r.is_not_set_up, (r.invoice_text is not null) as invoice_sent, r.source_file
from ranked r
left join {{ ref('dim_property') }} p on p.property_key = r.property_key
where r.rn = 1
