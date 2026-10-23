{{ config(materialized='view') }}

-- One row per electricity / gas bill line from the sheet "utility bill" (property x bill).
-- A property row with a bill type but nothing else means the bill has not been set up yet; it is kept so it can be followed up.
-- The address is carried down for extra bills of the same property (rows with an amount only).

with src as (
    select *, nullif(regexp_replace(trim(c_a), '[(（].*$', ''), '') as address_here
    from {{ source('bronze', 'utility_bill') }}
    where _row_number > 1
),
grouped as (
    select *,
        count(case when address_here is not null then 1 end) over (partition by _source_file order by _row_number) as grp,
        (address_here ~ '^[0-9]') as is_property_row
    from src
),
carried as (
    select *,
        max(case when is_property_row then address_here end) over (partition by _source_file, grp) as address_raw
    from grouped
),
kept as (
    select *, regexp_split_to_array(trim(c_c), '\s*(?:--|-|\sto\s)\s*') as period_parts
    from carried
    where address_raw is not null
),
parsed as (
    select *,
        case when array_length(period_parts, 1) = 2 then trim(period_parts[1]) end as start_raw,
        case when array_length(period_parts, 1) = 2 then trim(period_parts[2]) end as end_raw
    from kept
),
dated as (
    select *,
        {{ parse_loose_date('start_raw') }} as period_start,
        {{ parse_loose_date('end_raw') }}   as period_end,
        {{ first_date('c_d') }}             as due_date,
        (regexp_match(c_e, '^[0-9]+(?:\.[0-9]+)?'))[1]::numeric as amount_first_number
    from parsed
)

select
    md5(_file_sha256 || '|' || _row_number::text || '|utility') as utility_bill_id,
    _source_file as source_file,
    _row_number  as source_row_number,
    address_raw,
    nullif(trim(c_b), '') as bill_type_raw,
    case
        when c_b ~ '电' and c_b ~ '(煤)?气' then 'electricity_and_gas'
        when c_b ~ '电' then 'electricity'
        when c_b ~ '气' then 'gas'
    end as bill_type,
    nullif(trim(c_c), '') as period_text,
    period_start,
    period_end,
    due_date,
    amount_first_number as amount,
    -- the amount cell sometimes holds a note, e.g. "600(sam said charge 600)"
    (c_e is not null and c_e !~ '^[0-9]+(\.[0-9]+)?$') as amount_has_note,
    nullif(trim(c_e), '') as amount_text,
    nullif(trim(c_f), '') as calc_file_text,
    nullif(trim(c_g), '') as invoice_text,
    {{ nearest_month_day('c_g', 'coalesce(period_end, due_date)') }} as invoice_sent_date,
    (select sa.staff_name from regexp_matches(coalesce(c_g, ''), '[A-Za-z]+', 'g') t(m)
       join {{ ref('staff_aliases') }} sa on sa.alias = lower(t.m[1]) limit 1) as invoice_sent_by,
    nullif(trim(c_h), '') as payment_check_text,
    {{ nearest_month_day('c_h', 'coalesce(period_end, due_date)') }} as payment_check_date,
    (is_property_row and nullif(trim(c_e), '') is null and nullif(trim(c_c), '') is null) as is_not_set_up
from dated
