-- The "days" columns written in the sheet must equal the difference between the dates next to them.
select cash_receipt_id, address_raw, handover_gap_days, handover_gap_days_written, bank_gap_days, bank_gap_days_written
from {{ ref('fact_rent_cash_receipt') }}
where handover_gap_days is distinct from handover_gap_days_written
   or bank_gap_days     is distinct from bank_gap_days_written
