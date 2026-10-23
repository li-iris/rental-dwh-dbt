{{ config(materialized='view') }}

-- One row per living space (living room, master room, room 2-5) of a property, from the condition-report
-- columns of the sheet "Profit". Each space has orientation, furniture, balcony and (rooms only) built-in wardrobe.
-- A "/" in the sheet means the property has no such room.

with src as (
    select * from {{ source('bronze', 'profit_monthly') }}
    where _row_number > 1 and c_a is not null
),

spaces as (
    select _file_sha256, _row_number, 'living_room' as space_code, 1 as space_order,
           c_ad as orientation, c_ae as furniture, c_af as balcony, null::text as wardrobe from src
    union all
    select _file_sha256, _row_number, 'master_room', 2, c_ag, c_ah, c_ai, c_aj from src
    union all
    select _file_sha256, _row_number, 'room2', 3, c_ak, c_al, c_am, c_an from src
    union all
    select _file_sha256, _row_number, 'room3', 4, c_ao, c_ap, c_aq, c_ar from src
    union all
    select _file_sha256, _row_number, 'room4', 5, c_as, c_at, c_au, c_av from src
    union all
    select _file_sha256, _row_number, 'room5', 6, c_aw, c_ax, c_ay, c_az from src
)

select
    s.source_file_sha256,
    s.source_row_number,
    s.address_raw,
    sp.space_code,
    sp.space_order,
    nullif(trim(sp.orientation), '')   as orientation_raw,
    nullif(trim(sp.furniture), '')     as furniture_raw,
    nullif(trim(sp.balcony), '')       as balcony_raw,
    nullif(trim(sp.wardrobe), '')      as wardrobe_raw
from (
    select _file_sha256 as source_file_sha256, _row_number as source_row_number, trim(c_a) as address_raw
    from src
) s
join spaces sp
  on sp._file_sha256 = s.source_file_sha256
 and sp._row_number  = s.source_row_number
where nullif(trim(sp.orientation), '/') is not null
  and trim(sp.orientation) <> ''
