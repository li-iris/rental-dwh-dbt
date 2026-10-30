-- PostgreSQL answer for transforms.rent_received_trend, computed on the dbt report rpt_rent_received_month:
-- per property, the change against the previous calendar month (empty when that month has no row) and a running total.
-- Run by spark/export_inputs.py; the Spark result (built from Spark's own recomputed report) must match it row for row.
with ordered as (
    select
        property_id,
        month_start,
        total_recorded_aud,
        lag(month_start)        over w                                                as prev_month_start,
        lag(total_recorded_aud) over w                                                as prev_total,
        sum(total_recorded_aud) over (w rows between unbounded preceding and current row) as running_recorded_aud
    from {gold}.rpt_rent_received_month
    window w as (partition by property_id order by month_start)
),
with_prev as (
    select *,
           case when prev_month_start = (month_start - interval '1 month')::date then prev_total end as prev_month_recorded_aud
    from ordered
)
select
    property_id,
    month_start,
    total_recorded_aud,
    prev_month_recorded_aud,
    total_recorded_aud - prev_month_recorded_aud as mom_change_aud,
    running_recorded_aud
from with_prev
