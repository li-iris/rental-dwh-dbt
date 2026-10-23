-- In the sheet "Profit" the total must equal the room rents plus garage rent minus the bill amount.
select property_id, address_raw, total_rent_written,
       coalesce(master_room_rent, 0) + coalesce(room1_rent, 0) + coalesce(room2_rent, 0) + coalesce(room3_rent, 0)
         + coalesce(room4_rent, 0) + coalesce(room5_rent, 0) + coalesce(garage_rent, 0) - coalesce(bill_amount, 0) as total_recomputed
from {{ ref('dim_property_profile') }}
where abs(total_rent_written - (
        coalesce(master_room_rent, 0) + coalesce(room1_rent, 0) + coalesce(room2_rent, 0) + coalesce(room3_rent, 0)
        + coalesce(room4_rent, 0) + coalesce(room5_rent, 0) + coalesce(garage_rent, 0) - coalesce(bill_amount, 0))) > 0.01
