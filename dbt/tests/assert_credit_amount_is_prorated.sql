-- Fails if credit_amount differs from weekly_rent * days / 7 by 1 dollar or more.
select *
from {{ ref('stg_rent_credit') }}
where abs(credit_amount - weekly_rent * days / 7.0) >= 1
