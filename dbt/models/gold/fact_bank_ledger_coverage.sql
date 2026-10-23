-- One row per date range of one money account that has been entered into the books.
-- Accounts: company_card, sole_card, rmb, office_cash.
-- gap_days_before = days between the end of the previous range of the same account and the start of this one
-- (0 = no gap, positive = days never entered, negative = overlap).

with ranges as (
    select
        md5(source_file_sha256 || '|' || source_row_number::text || '|' || account) as coverage_id,
        account,
        period_start,
        period_end,
        days_written,
        period_end - period_start + 1                                  as days_counted,
        nullif(initcap(btrim(recorded_by_raw)), '')                    as recorded_by,
        recorded_date,
        recorded_date - period_end                                     as days_to_record,
        import_flag                                                    as is_imported,
        note
    from {{ ref('stg_bank_ledger_coverage') }}
)

select
    r.*,
    r.period_start - lag(r.period_end) over (partition by r.account order by r.period_start, r.period_end) - 1
        as gap_days_before
from ranges r
