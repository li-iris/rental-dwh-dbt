{{ config(severity='warn') }}
-- The tenant was told less than routine_inspection_notice_days before a routine inspection (only rows with both dates).
select notice_id, property_id, address_raw, notice_date, notice_given_date, notice_date - notice_given_date as days_notice
from {{ ref('fact_inspection_notice') }}
where notice_type = 'routine' and notice_given_date is not null and notice_date is not null
  and notice_date - notice_given_date < {{ rule('routine_inspection_notice_days') }}
