{{ config(severity='warn') }}
-- Warning only: credit was booked, but the booked amount differs from the expected amount.
select address_raw, start_date, end_date, credit_amount, booked_amount,
       booked_amount - credit_amount as difference
from {{ ref('stg_rent_credit') }}
where booked_amount is not null
  and abs(booked_amount - credit_amount) >= 1
