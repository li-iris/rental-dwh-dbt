{{ config(severity='warn') }}
-- Business follow-up: the inspection date cell is empty or written in a way that cannot be read as a date.
select notice_type, address_raw, source_file, source_row_number
from {{ ref('stg_inspection_notice') }}
where notice_date is null
