-- One row per staff member. Names are written in many ways in the sheets (Sam, sAM, Jordon ...);
-- the seed staff_aliases maps each spelling to one name.

select
    md5(staff_name)         as staff_id,
    staff_name,
    count(*)                as spellings_known
from {{ ref('staff_aliases') }}
group by staff_name
