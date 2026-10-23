-- Every property_id used in a fact or detail table must exist in dim_property (nothing points at a missing property).
with used as (
    select 'fact_rmb_receipt' as tbl, property_id from {{ ref('fact_rmb_receipt') }}
    union all select 'fact_rent_account_check', property_id from {{ ref('fact_rent_account_check') }}
    union all select 'fact_rent_cash_receipt', property_id from {{ ref('fact_rent_cash_receipt') }}
    union all select 'fact_parking_lease', property_id from {{ ref('fact_parking_lease') }}
    union all select 'dim_property_profile', property_id from {{ ref('dim_property_profile') }}
    union all select 'dim_room_profile', property_id from {{ ref('dim_room_profile') }}
    union all select 'dim_property_item', property_id from {{ ref('dim_property_item') }}
    union all select 'dim_tenancy', property_id from {{ ref('dim_tenancy') }}
    union all select 'dim_room', property_id from {{ ref('dim_room') }}
    union all select 'fact_turnover_case', property_id from {{ ref('fact_turnover_case') }}
    union all select 'fact_process_case', property_id from {{ ref('fact_process_case') }}
    union all select 'fact_rent_roll_month', property_id from {{ ref('fact_rent_roll_month') }}
)
select u.tbl, u.property_id
from used u
left join {{ ref('dim_property') }} p on p.property_id = u.property_id
where u.property_id is not null and p.property_id is null
