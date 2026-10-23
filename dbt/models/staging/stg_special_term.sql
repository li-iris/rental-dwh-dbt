{{ config(materialized='view') }}

-- Special clauses from the Excel workbooks plus clauses typed into entry.special_term.

select * from {{ ref('stg_special_term_excel') }}

union all

select
    md5('entry|' || e.special_term_entry_id::text || '|special_term') as special_term_id,
    'entry'::text                                                     as source_file,
    e.special_term_entry_id::int                                      as source_row_number,
    e.address                                                         as address_raw,
    e.term_text,
    nullif(btrim(e.status_text), '')                                  as status_text,
    e.recorded_date::text                                             as recorded_text,
    e.recorded_by,
    (nullif(btrim(e.status_text), '') is not null)                    as has_status,
    null::text                                                        as amount_symbol,
    null::text                                                        as amount_text
from {{ source('entry', 'special_term') }} e
