-- Per property and month: what the leases say should come in, next to everything recorded as received
-- (cash and RMB from the workbooks plus payments typed into entry.rent_payment).
-- A positive difference means more was recorded than expected.
with typed as (
    select property_id, paid_month, sum(amount) as typed_received_aud
    from {{ ref('fact_rent_payment') }}
    where property_id is not null
    group by 1, 2
)
select
    r.property_id,
    r.month_start,
    r.rent_basis,
    r.expected_rent_aud,
    r.expected_rent_with_rules_aud,
    r.cash_received_aud,
    r.rmb_received_aud,
    t.typed_received_aud,
    coalesce(r.cash_received_aud, 0) + coalesce(r.rmb_received_aud, 0) + coalesce(t.typed_received_aud, 0) as total_recorded_aud,
    coalesce(r.cash_received_aud, 0) + coalesce(r.rmb_received_aud, 0) + coalesce(t.typed_received_aud, 0)
        - coalesce(r.expected_rent_with_rules_aud, r.expected_rent_aud, 0)                                 as recorded_minus_expected_with_rules_aud
from {{ ref('fact_rent_roll_month') }} r
left join typed t on t.property_id = r.property_id and t.paid_month = r.month_start
