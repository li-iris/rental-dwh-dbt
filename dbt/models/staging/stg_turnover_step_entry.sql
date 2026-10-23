-- One row per step cell that has something written in it ("12.5 Jordan", "是12.16 Jordan", "已登记", ...).
-- Steps with an empty cell have no row here; gold adds them as "no record".
-- Which columns are steps, and their deadline rules, come from the seed turnover_step_catalog.
-- Cells carry day.month only, so the year is inferred (see year_was_inferred).

with entries as (
    select
        cs.case_id,
        cat.step_code,
        trim(kv.v)                                                                       as raw_text,
        -- reference date used to guess the missing year
        coalesce(cs.new_move_in_date, cs.actual_move_out_date, cs.old_contract_end_date,
                 snap.as_of_date)                                                        as year_anchor
    from {{ source('bronze', 'tenancy_lifecycle') }} t
    join {{ ref('stg_turnover_case') }} cs
      on cs.source_file_sha256 = t._file_sha256
     and cs.source_row_number  = t._row_number
    left join {{ ref('source_snapshot_order') }} snap
      on snap.source_file = cs.source_file
    cross join lateral jsonb_each_text(to_jsonb(t)) as kv(k, v)
    join {{ ref('turnover_step_catalog') }} cat
      on kv.k = 'c_' || lower(cat.column_letter)
    where nullif(trim(kv.v), '') is not null
),

parsed as (
    select *,
        -- "9.25 Sam": day.month without a year
        regexp_match(raw_text, '(^|[^0-9])([0-9]{1,2})\.([0-9]{1,2})([^0-9]|$)')              as md,
        -- "26.1.12": a two-digit year is written, so no guessing is needed
        regexp_match(raw_text, '(^|[^0-9])(2[0-9])\.([0-9]{1,2})\.([0-9]{1,2})([^0-9]|$)')    as ymd,
        raw_text ~ '^是'                                                                      as says_yes,
        raw_text ~ '^否'                                                                      as says_no,
        raw_text ~ '已'                                                                       as says_already_done,
        initcap(substring(raw_text from '[A-Za-z]+'))                                         as done_by
    from entries
),

-- no year written: try the year before, same and after the reference date, keep the closest one
candidates as (
    select p.case_id, p.step_code,
        (make_date(y.yr, 1, 1)
            + ((p.md[2])::int - 1) * interval '1 month'
            + ((p.md[3])::int - 1) * interval '1 day')::date as candidate_date,
        (p.md[2])::int                                       as md_month,
        p.year_anchor
    from parsed p
    cross join lateral generate_series(
        extract(year from p.year_anchor)::int - 1,
        extract(year from p.year_anchor)::int + 1) as y(yr)
    where p.md is not null
      and p.ymd is null
      and p.year_anchor is not null
      and (p.md[2])::int between 1 and 12
),

best as (
    select distinct on (case_id, step_code)
        case_id, step_code, candidate_date
    from candidates
    where extract(month from candidate_date) = md_month   -- drops impossible dates such as 2.30
    order by case_id, step_code, abs(candidate_date - year_anchor)
)

select
    p.case_id,
    p.step_code,
    p.raw_text,
    case when p.md is not null or p.ymd is not null then 'dated'
         when p.says_yes                            then 'yes'
         when p.says_no                             then 'no'
         when p.says_already_done                   then 'text_done'
         else 'text_only' end                                           as entry_type,
    ((p.md is not null or p.ymd is not null or p.says_yes or p.says_already_done)
        and not p.says_no)                                              as is_done,
    p.done_by,
    case when p.ymd is not null
         then make_date(2000 + (p.ymd[2])::int, 1, 1)
              + ((p.ymd[3])::int - 1) * interval '1 month'
              + ((p.ymd[4])::int - 1) * interval '1 day'
         else b.candidate_date end::date                                as step_date,
    (p.md is not null and p.ymd is null)                                as year_was_inferred
from parsed p
left join best b using (case_id, step_code)
