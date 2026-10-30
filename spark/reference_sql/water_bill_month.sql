-- PostgreSQL answer for transforms.water_bill_month: water bills per property and billing month (month of period_start).
-- Run by spark/export_inputs.py on the gold tables; the Spark result must match it row for row.
select
    property_id,
    date_trunc('month', period_start)::date                                            as bill_month,
    count(*)                                                                           as bills,
    sum(amount)                                                                        as total_amount,
    count(*) filter (where follow_up_status <> 'closed')                               as open_bills,
    coalesce(sum(amount) filter (where follow_up_status <> 'closed'), 0)               as open_amount,
    count(*) filter (where follow_up_status in ('invoice_overdue', 'payment_overdue')) as overdue_bills,
    count(*) filter (where may_be_unrecoverable)                                       as may_be_unrecoverable_bills
from {gold}.fact_water_bill
group by 1, 2
