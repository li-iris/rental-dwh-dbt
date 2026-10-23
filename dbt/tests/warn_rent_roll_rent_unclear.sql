{{ config(severity='warn') }}
-- Business follow-up: for these property-months the expected rent is left empty because the rents in the tenancy list cannot be told apart.
-- unclear_reason: rent_missing, unit_and_room_rents_mixed (a whole-unit rent next to room rents), different_unit_rents.
-- Rule used: a weekly rent of 600 or less is one room, above 600 is the whole unit.
select property_id, month_start, unclear_reason
from {{ ref('fact_rent_roll_month') }}
where rent_basis = 'unclear'
