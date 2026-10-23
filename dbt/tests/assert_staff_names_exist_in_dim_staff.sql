-- Every staff name written into a fact table must be a staff member in dim_staff (spellings are mapped by seed staff_aliases).
with used as (
    select 'fact_rmb_receipt.recorded_by' as col, recorded_by as staff_name from {{ ref('fact_rmb_receipt') }}
    union all select 'fact_rent_cash_receipt.collected_by', collected_by from {{ ref('fact_rent_cash_receipt') }}
    union all select 'fact_rent_cash_receipt.banked_by', banked_by from {{ ref('fact_rent_cash_receipt') }}
    union all select 'fact_water_bill.invoice_sent_by', invoice_sent_by from {{ ref('fact_water_bill') }}
    union all select 'fact_utility_bill.invoice_sent_by', invoice_sent_by from {{ ref('fact_utility_bill') }}
    union all select 'fact_inspection_notice.sent_by', sent_by from {{ ref('fact_inspection_notice') }}
    union all select 'fact_inspection_notice.pre_check_by', pre_check_by from {{ ref('fact_inspection_notice') }}
    union all select 'fact_inspection_notice.attended_by', attended_by from {{ ref('fact_inspection_notice') }}
    union all select 'fact_special_term.recorded_by', recorded_by from {{ ref('fact_special_term') }}
    union all select 'fact_process_step.done_by', done_by from {{ ref('fact_process_step') }}
)
select distinct u.col, u.staff_name
from used u
left join {{ ref('dim_staff') }} s on s.staff_name = u.staff_name
where u.staff_name is not null and s.staff_name is null
