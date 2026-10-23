-- One row per rent account check: a property, a check round (1-3), the date, the checker and the outcome.

select
    md5(c.source_file_sha256 || '|' || c.source_row_number::text || '|' || c.check_round::text) as account_check_id,
    p.property_id,
    c.address_raw,
    c.check_round,
    c.check_date,
    nullif(initcap(btrim(c.checked_by)), '')                         as checked_by,
    c.result_note,
    -- 'ok' when the note says there is no problem; anything else written is an 'issue' to follow up
    case
        when c.result_note is null                                                  then null
        when c.result_note ~ '没有问题|没问题|无问题'
             and c.result_note !~ '没有支付|没交|没有交'                               then 'ok'
        else 'issue'
    end                                                              as result_status,
    nullif(btrim(c.payment_method), '')                              as payment_method,
    nullif(btrim(c.resolution), '')                                  as resolution
from {{ ref('stg_rent_reconciliation_check') }} c
left join {{ ref('stg_address_parsed') }} a
       on a.src = 'reconciliation' and a.address_raw = c.address_raw
left join {{ ref('dim_property') }} p
       on p.property_key = a.property_key
