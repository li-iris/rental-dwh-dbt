-- Candidate tenancies for each room turnover case. The turnover sheet has no tenant name and often no room, so a case
-- cannot be tied to one tenancy for certain. This table lists every tenancy of the same property whose lease dates are
-- within 30 days of the turnover dates:
--   role 'leaving'  : lease_end   close to the move-out date used for the case
--   role 'arriving' : lease_start close to the new tenant's move-in date
-- is_only_candidate = true means exactly one tenancy fits, which is a safe link. Otherwise someone has to choose.

with leaving as (
    select c.case_id, 'leaving' as role, t.tenancy_id, abs(t.lease_end - c.move_out_date_used) as days_apart
    from {{ ref('fact_turnover_case') }} c
    join {{ ref('dim_tenancy') }} t on t.property_id = c.property_id
    where c.move_out_date_used is not null and abs(t.lease_end - c.move_out_date_used) <= 30
),
arriving as (
    select c.case_id, 'arriving', t.tenancy_id, abs(t.lease_start - c.new_move_in_date)
    from {{ ref('fact_turnover_case') }} c
    join {{ ref('dim_tenancy') }} t on t.property_id = c.property_id
    where c.new_move_in_date is not null and abs(t.lease_start - c.new_move_in_date) <= 30
),
unioned as (
    select * from leaving union all select * from arriving
)
select
    case_id, role, tenancy_id, days_apart,
    count(*) over (partition by case_id, role) as candidates_for_case_role,
    (count(*) over (partition by case_id, role) = 1) as is_only_candidate
from unioned
