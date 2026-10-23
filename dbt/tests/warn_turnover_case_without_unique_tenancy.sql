{{ config(severity='warn') }}
-- Business follow-up: a room turnover with a move-out date that cannot be tied to exactly one leaving tenancy.
select c.case_id, c.address_raw, c.move_out_date_used,
       coalesce(max(k.candidates_for_case_role), 0) as candidate_tenancies
from {{ ref('fact_turnover_case') }} c
left join {{ ref('fact_turnover_tenancy_candidate') }} k on k.case_id = c.case_id and k.role = 'leaving'
where c.move_out_date_used is not null
group by c.case_id, c.address_raw, c.move_out_date_used
having coalesce(max(k.candidates_for_case_role), 0) <> 1
