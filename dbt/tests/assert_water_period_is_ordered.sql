-- A billing period must not end before it starts.
select water_bill_id, address_raw, period_text from {{ ref('fact_water_bill') }} where period_start > period_end
