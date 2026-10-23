-- One row per property x calendar month: what the tenancy list says the rent should be, next to what the workbooks
-- record as received. The window is set with --vars rent_roll_start / rent_roll_through (default: 2025-07-01 .. the end of the current month).
--
-- How the expected rent is worked out. In dim_tenancy the weekly rent is written on every tenant row. The owner's rule:
-- a rent of 600 or less (variable whole_unit_rent_over) is the rent of ONE ROOM, a rent above 600 is the rent of the WHOLE UNIT.
-- A day is judged from the distinct leases (same dates and rent) active in the property that day:
--   unit_rent             one whole-unit rent (the same value repeated for each co-tenant counts once)
--   room_rent             exactly one room rent
--   room_rents_estimated  several room rents, added up; may be wrong if two people share one room or the rents are shares
--   unclear               left empty: a missing rent, a whole-unit rent next to room rents, or two different whole-unit rents
-- The owner said to leave anything unclear empty until the data is filled in properly.
--
-- Recorded money is only what the workbooks hold: RMB receipts, cash receipts (by the month they pay for) and vacancy credits
-- spread over their days. The workbooks hold no bank transaction detail, so "no recorded payment" does not mean "not paid".

{% set start_date = var('rent_roll_start', '2025-07-01') %}
{# default end of the window = the last day of the current month, so the roll grows with time; override with --vars #}
{% set through_date = var('rent_roll_through', '') %}
{% set through_sql = "date '" ~ through_date ~ "'" if through_date else "(date_trunc('month', current_date) + interval '1 month - 1 day')::date" %}
{% set unit_over = var('whole_unit_rent_over', 600) %}

with months as (
    select m::date as month_start,
           (m + interval '1 month' - interval '1 day')::date as month_end
    from generate_series(date '{{ start_date }}', {{ through_sql }}, interval '1 month') m
),

lease_groups as (
    -- rent_class: a property that is rented room by room (dim_property.is_rented_by_room) has only room rents, whatever the amount;
    -- otherwise the owner's rule applies (above the threshold = whole unit, at or below = one room)
    select distinct t.property_id, t.lease_start, t.lease_end, t.unit_weekly_rent,
           case when p.is_rented_by_room or t.unit_weekly_rent <= {{ unit_over }} then 'room'
                when t.unit_weekly_rent > {{ unit_over }} then 'unit' end as rent_class
    from {{ ref('dim_tenancy') }} t
    join {{ ref('dim_property') }} p on p.property_id = t.property_id
    where t.lease_start is not null and t.lease_end is not null and t.lease_end >= t.lease_start
),

property_day as (
    select
        g.property_id,
        d::date as day,
        bool_or(g.unit_weekly_rent is null)                                                  as any_rent_missing,
        count(*) filter (where g.rent_class = 'unit')                          as unit_leases,
        count(distinct g.unit_weekly_rent) filter (where g.rent_class = 'unit') as distinct_unit_rents,
        count(*) filter (where g.rent_class = 'room')                         as room_leases,
        max(g.unit_weekly_rent) filter (where g.rent_class = 'unit')           as unit_rent,
        sum(g.unit_weekly_rent) filter (where g.rent_class = 'room')          as room_rent_sum,
        count(g.unit_weekly_rent)                                                             as leases_with_rent,
        (array_agg(g.unit_weekly_rent order by g.lease_start desc)
            filter (where g.rent_class = 'unit'))[1]                           as latest_unit_rent
    from lease_groups g
    cross join lateral generate_series(
        greatest(g.lease_start, date '{{ start_date }}'),
        least(g.lease_end, {{ through_sql }}),
        interval '1 day') d
    group by g.property_id, d
),

property_day_judged as (
    select *,
        case
            when any_rent_missing                         then 'unclear'
            when unit_leases > 0 and room_leases > 0      then 'unclear'
            when distinct_unit_rents > 1                  then 'unclear'
            when unit_leases > 0                          then 'unit_rent'
            when room_leases = 1                          then 'room_rent'
            else 'room_rents_estimated'
        end as day_basis,
        case
            when any_rent_missing                         then 'rent_missing'
            when unit_leases > 0 and room_leases > 0      then 'unit_and_room_rents_mixed'
            when distinct_unit_rents > 1                  then 'different_unit_rents'
        end as unclear_reason,
        case
            when any_rent_missing or (unit_leases > 0 and room_leases > 0) or distinct_unit_rents > 1 then null
            when unit_leases > 0 then unit_rent
            else room_rent_sum
        end as weekly_rent_used,
        -- Rules used when the day is unclear (assumed, not confirmed by the owner; the amount goes to expected_rent_with_rules_aud):
        --   a lease with no rent is ignored when another lease has one; a whole-unit rent replaces room rents written next to it
        --   (room rents are treated as its split); of two different whole-unit rents the newest lease wins.
        case
            when leases_with_rent = 0                         then null
            when unit_leases > 0                              then latest_unit_rent
            else room_rent_sum
        end as weekly_rent_with_rules,
        case
            when leases_with_rent = 0                                   then null
            when unit_leases > 0 and room_leases > 0                    then 'unit_rent_replaces_room_rents'
            when distinct_unit_rents > 1                                then 'newest_unit_rent_used'
            when any_rent_missing                                       then 'lease_without_rent_ignored'
        end as rule_applied
    from property_day
),

expected as (
    select
        pd.property_id,
        m.month_start,
        count(*)                                                       as days_with_tenancy,
        count(*) filter (where pd.day_basis = 'unclear')               as days_rent_unclear,
        sum(pd.weekly_rent_used / 7.0)                                 as expected_aud_clear_days,
        sum(pd.weekly_rent_with_rules / 7.0)                           as expected_aud_with_rules,
        string_agg(distinct pd.rule_applied, ', ')                     as rules_applied,
        count(*) filter (where pd.day_basis = 'unit_rent')             as unit_days,
        count(*) filter (where pd.day_basis = 'room_rent')             as room_days,
        count(*) filter (where pd.day_basis = 'room_rents_estimated')  as estimated_days,
        min(pd.unclear_reason)                                         as unclear_reason
    from property_day_judged pd
    join months m on pd.day between m.month_start and m.month_end
    group by pd.property_id, m.month_start
),

cash as (
    select property_id, date_trunc('month', rent_month)::date as month_start, sum(cash_amount) as cash_received_aud
    from {{ ref('fact_rent_cash_receipt') }}
    group by 1, 2
),

rmb as (
    select property_id, date_trunc('month', receipt_date)::date as month_start, sum(aud_amount) as rmb_received_aud
    from {{ ref('fact_rmb_receipt') }}
    group by 1, 2
),

credit as (
    select
        p.property_id,
        m.month_start,
        sum(c.credit_amount * (least(c.end_date, m.month_end) - greatest(c.start_date, m.month_start) + 1)::numeric
            / nullif(c.end_date - c.start_date + 1, 0)) as vacancy_credit_aud
    from {{ ref('stg_rent_credit') }} c
    join {{ ref('stg_address_parsed') }} a on a.src = 'rent_credit' and a.address_raw = c.address_raw
    join {{ ref('dim_property') }} p on p.property_key = a.property_key
    join months m on c.start_date <= m.month_end and c.end_date >= m.month_start
    where c.start_date is not null and c.end_date is not null
    group by 1, 2
),

keys as (
    select property_id, month_start from expected
    union select property_id, month_start from cash
    union select property_id, month_start from rmb
    union select property_id, month_start from credit
)

select
    k.property_id,
    k.month_start,
    (k.month_start + interval '1 month' - interval '1 day')::date                       as month_end,
    coalesce(e.days_with_tenancy, 0)                                                    as days_with_tenancy,
    coalesce(e.days_rent_unclear, 0)                                                    as days_rent_unclear,
    case
        when e.property_id is null             then 'no_tenancy'
        when e.days_rent_unclear > 0           then 'unclear'
        when e.estimated_days > 0              then 'room_rents_estimated'
        when e.unit_days = e.days_with_tenancy then 'unit_rent'
        when e.room_days = e.days_with_tenancy then 'room_rent'
        else 'rent_type_changed_in_month'
    end                                                                                 as rent_basis,
    e.unclear_reason                                                                    as unclear_reason,
    -- Expected rent after applying the default rules (see docs/BUSINESS_RULES.md); equals expected_rent_aud when no rule was needed.
    round(e.expected_aud_with_rules, 2)                                                 as expected_rent_with_rules_aud,
    e.rules_applied                                                                     as rent_rules_applied,
    case when e.property_id is not null and e.days_rent_unclear = 0
         then round(e.expected_aud_clear_days, 2) end                                   as expected_rent_aud,
    round(cash.cash_received_aud, 2)                                                    as cash_received_aud,
    round(rmb.rmb_received_aud, 2)                                                      as rmb_received_aud,
    round(credit.vacancy_credit_aud, 2)                                                 as vacancy_credit_aud,
    (cash.property_id is not null or rmb.property_id is not null or credit.property_id is not null) as has_recorded_payment,
    case when e.property_id is not null and e.days_rent_unclear = 0 and e.estimated_days = 0
          and (cash.property_id is not null or rmb.property_id is not null or credit.property_id is not null)
         then round(coalesce(cash.cash_received_aud, 0) + coalesce(rmb.rmb_received_aud, 0) + coalesce(credit.vacancy_credit_aud, 0)
                    - e.expected_aud_clear_days, 2) end                                 as recorded_minus_expected_aud
from keys k
left join expected e on e.property_id = k.property_id and e.month_start = k.month_start
left join cash   on cash.property_id   = k.property_id and cash.month_start   = k.month_start
left join rmb    on rmb.property_id    = k.property_id and rmb.month_start    = k.month_start
left join credit on credit.property_id = k.property_id and credit.month_start = k.month_start
