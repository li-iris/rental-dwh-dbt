{{ config(materialized='view') }}

-- The business rules in force (numbers and where they come from), readable in Navicat next to the data.
-- Edit the seed file seeds/business_rules.csv, not this view.
select rule_id, value::numeric as value, unit, applies_to, description, decided_by, basis
from {{ ref('business_rules') }}
