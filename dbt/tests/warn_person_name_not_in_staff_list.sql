{{ config(severity='warn') }}
-- Warning only: a name written in a recorder / checker column is not in the seed staff_aliases.
-- Either add the spelling to the seed, or it is a typo in the sheet.
with used as (
    select checked_by   as person_name, 'fact_rent_account_check' as found_in from {{ ref('fact_rent_account_check') }}
    union all
    select recorded_by,                 'fact_rmb_receipt'                    from {{ ref('fact_rmb_receipt') }}
    union all
    select recorded_by,                 'fact_bank_ledger_coverage'           from {{ ref('fact_bank_ledger_coverage') }}
    union all
    select collected_by,                'fact_rent_cash_receipt'              from {{ ref('fact_rent_cash_receipt') }}
    union all
    select banked_by,                   'fact_rent_cash_receipt'              from {{ ref('fact_rent_cash_receipt') }}
    union all
    select done_by,                     'stg_turnover_step_entry'             from {{ ref('stg_turnover_step_entry') }}
)
select person_name, found_in, count(*) as times_used
from used
where person_name is not null
  and lower(person_name) not in (select alias from {{ ref('staff_aliases') }})
group by 1, 2
