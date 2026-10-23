{{ config(severity='warn') }}
-- Business follow-up: an address in the water, utility or moving sheet is not one of the managed properties (typo or ended).
select 'water' as sheet, address_raw from {{ ref('fact_water_bill') }} where property_id is null
union all
select 'utility', address_raw from {{ ref('fact_utility_bill') }} where property_id is null
union all
select 'moving', address_raw from {{ ref('fact_moving_job') }} where property_id is null
