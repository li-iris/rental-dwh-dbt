-- A billing period must not end before it starts.
select utility_bill_id, address_raw, period_text from {{ ref('fact_utility_bill') }} where period_start > period_end
