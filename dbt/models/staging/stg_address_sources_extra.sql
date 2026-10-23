{{ config(materialized='view') }}

-- Raw addresses from the sheets added after the first address model was written.
-- Each branch gives the sheet name (src) and the address as written. stg_address_parsed unions this in.
-- A property is written once on its first row in some sheets; rows without an address inherit it in their own model.

select 'rent_cash' as src, trim(c_d) as address_raw
from {{ source('bronze', 'rent_cash') }}
where _row_number > 1 and c_d ~ '^[0-9]'

union
select 'property_items', trim(c_a)
from {{ source('bronze', 'property_items') }}
where _row_number > 1 and c_a ~ '^[0-9]'

union
-- parking sheets are written "Street, unit/number, Parking Space"; rewritten to "unit/number Street"
select 'parking_lease', {{ parking_address_standard('c_a') }}
from {{ source('bronze', 'garage_parking') }}
where _row_number > 1 and c_a is not null
union
select 'parking_lease', {{ parking_address_standard('c_e') }}
from {{ source('bronze', 'garage_parking') }}
where _row_number > 1 and c_e is not null
union
select 'parking_lease', {{ parking_address_standard('c_j') }}
from {{ source('bronze', 'garage_parking') }}
where _row_number > 1 and c_j is not null

union
-- paperwork checklists (new tenant, renewal, contract transfer): the address is in column A
select 'process_list', trim(c_a) from {{ source('bronze', 'rental_application') }} where _row_number > 1 and c_a ~ '^[0-9]'
union
select 'process_list', trim(c_a) from {{ source('bronze', 'rent_review') }} where _row_number > 1 and c_a ~ '^[0-9]'
union
select 'process_list', trim(c_a) from {{ source('bronze', 'contract_transfer') }} where _row_number > 1 and c_a ~ '^[0-9]'

union
-- inspection / notice sheet: three side-by-side blocks (routine in A, fire in M, other notices in U)
select 'inspection_list', trim(c_a) from {{ source('bronze', 'inspection_notice') }} where _row_number > 2 and c_a ~ '^[0-9]'
union
select 'inspection_list', trim(c_m) from {{ source('bronze', 'inspection_notice') }} where _row_number > 2 and c_m ~ '^[0-9]'
union
select 'inspection_list', trim(c_u) from {{ source('bronze', 'inspection_notice') }} where _row_number > 2 and c_u ~ '^[0-9]'
union
select 'special_terms', trim(c_a) from {{ source('bronze', 'special_terms') }} where _row_number > 1 and c_a ~ '^[0-9]' and nullif(trim(c_b), '') is not null

union
-- bill and moving sheets: addresses are already cleaned and carried down in their own silver models
select 'water_list', address_raw from {{ ref('stg_water_bill') }}
union
select 'utility_list', address_raw from {{ ref('stg_utility_bill') }}
union
select 'moving_list', address_raw from {{ ref('stg_moving_job') }}

union
-- rows typed into Navicat (schema entry). entry.property is the master list: its addresses are real properties.
select 'entry_property', address from {{ source('entry', 'property') }}
union
select 'tenant_list', address from {{ source('entry', 'tenancy') }}
union
select 'inspection_list', address from {{ source('entry', 'inspection_notice') }}
union
select 'special_terms', address from {{ source('entry', 'special_term') }}
union
select 'parking_lease', address from {{ source('entry', 'parking_lease') }}
