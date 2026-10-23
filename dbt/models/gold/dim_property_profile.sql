-- One row per property with its descriptive facts: rents, contract tenants, agent, manager, bond, building facilities.
-- Source: the sheet "Profit" (a property information sheet). Only properties filled in that sheet appear here.

select
    p.property_id,
    s.address_raw,
    s.room_count,
    s.building_type,
    s.floor_number,
    s.access_to_unit,
    s.cooker_type,
    s.building_access,
    s.parking_note,
    s.parking_access,
    s.master_room_rent,
    s.room1_rent,
    s.room2_rent,
    s.room3_rent,
    s.room4_rent,
    s.room5_rent,
    s.garage_rent,
    s.bill_amount,
    s.total_rent_written,
    s.contract_tenants_raw,
    s.referral_fee,
    s.agent_raw  as agent_name,
    s.manager_raw as manager_name,
    s.bond
from {{ ref('stg_property_profile') }} s
left join {{ ref('stg_address_parsed') }} a
       on a.src = 'profit' and a.address_raw = s.address_raw
left join {{ ref('dim_property') }} p
       on p.property_key = a.property_key
