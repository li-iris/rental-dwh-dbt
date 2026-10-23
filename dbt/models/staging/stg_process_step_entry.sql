{{ config(materialized='view') }}

-- One row per step cell that has something written in it, for the three paperwork checklists
-- (see stg_process_case). Empty cells have no row here; gold adds them as "no record".
-- Which columns are steps comes from the seed process_step_catalog.
--
-- Cells hold "month.day Name" without a year ("12.6 Jordan"), or a two-digit year ("26.1.6 Jordan").
-- The missing year is chosen as the latest date that is not after a limit L, where
--   L = the earlier of (anchor_date + 60 days) and the newest date known in that workbook version.
-- Steps happen before the lease dates written in the sheet, so "nearest to the anchor" would often pick the wrong year.
-- Any run of 9 or more digits (phone numbers) is replaced by [number removed].

with cells as (
{% for proc in ['rental_application', 'rent_review', 'contract_transfer'] %}
    {% if not loop.first %}union all{% endif %}
    select c.case_id, c.process, c.source_file, c.source_file_sha256, c.anchor_date,
           cat.step_code, cat.kind,
           regexp_replace(trim(kv.v), '[0-9]{9,}', '[number removed]', 'g') as raw_text
    from {{ source('bronze', proc) }} t
    join {{ ref('stg_process_case') }} c
      on c.process = '{{ proc }}'
     and c.source_file_sha256 = t._file_sha256
     and c.source_row_number  = t._row_number
    cross join lateral jsonb_each_text(to_jsonb(t)) as kv(k, v)
    join {{ ref('process_step_catalog') }} cat
      on cat.process = '{{ proc }}'
     and kv.k = 'c_' || lower(cat.column_letter)
    where nullif(trim(kv.v), '') is not null
{% endfor %}
),

parsed as (
    select *,
        regexp_match(raw_text, '(^|[^0-9])([0-9]{1,2})\.([0-9]{1,2})([^0-9]|$)')            as md,
        regexp_match(raw_text, '(^|[^0-9])(2[0-9])\.([0-9]{1,2})\.([0-9]{1,2})([^0-9]|$)')  as ymd,
        raw_text ~ '^/'                                                                     as is_not_applicable,
        raw_text ~ '^是'                                                                    as says_yes,
        raw_text ~ '^否'                                                                    as says_no,
        raw_text ~ '已'                                                                     as says_already_done,
        (select sa.staff_name
           from regexp_matches(raw_text, '[A-Za-z]+', 'g') as t(m)
           join {{ ref('staff_aliases') }} sa on sa.alias = lower(t.m[1])
          limit 1)                                                                          as done_by,
        lower(raw_text) in (select alias from {{ ref('staff_aliases') }})                   as is_name_only
    from cells
),

explicit_dates as (
    select *,
        case when ymd is not null
             then make_date(2000 + (ymd[2])::int, 1, 1) + ((ymd[3])::int - 1) * interval '1 month'
                                                       + ((ymd[4])::int - 1) * interval '1 day' end::date as explicit_date
    from parsed
),

horizon as (
    select e.process, e.source_file,
           coalesce(max(o.as_of_date), max(e.explicit_date), max(e.anchor_date) + 60) as newest_known_date
    from explicit_dates e
    left join {{ ref('source_snapshot_order') }} o on o.source_file = e.source_file
    group by 1, 2
),

limits as (
    select e.case_id, e.step_code,
           least(coalesce(e.anchor_date + 60, h.newest_known_date), h.newest_known_date) as limit_date
    from explicit_dates e
    join horizon h on h.process = e.process and h.source_file = e.source_file
    where e.md is not null and e.ymd is null
),

candidates as (
    select l.case_id, l.step_code,
           (make_date(y.yr, 1, 1)
              + ((e.md[2])::int - 1) * interval '1 month'
              + ((e.md[3])::int - 1) * interval '1 day')::date as candidate_date,
           (e.md[2])::int as md_month,
           l.limit_date
    from limits l
    join explicit_dates e using (case_id, step_code)
    cross join lateral generate_series(extract(year from l.limit_date)::int - 1,
                                       extract(year from l.limit_date)::int) as y(yr)
    where (e.md[2])::int between 1 and 12
),

best as (
    select distinct on (case_id, step_code) case_id, step_code, candidate_date
    from candidates
    where extract(month from candidate_date) = md_month      -- drops impossible dates such as 2.30
      and candidate_date <= limit_date
    order by case_id, step_code, candidate_date desc
)

select
    e.case_id,
    e.process,
    e.step_code,
    e.raw_text,
    case
        when e.is_not_applicable                       then 'not_applicable'
        when e.md is not null or e.ymd is not null     then 'dated'
        when e.says_yes                                then 'yes'
        when e.says_no                                 then 'no'
        when e.says_already_done                       then 'text_done'
        when e.is_name_only                            then 'name_only'
        else 'text_only'
    end                                                                       as entry_type,
    case
        when e.is_not_applicable then false
        when e.kind = 'decision' then true
        else ((e.md is not null or e.ymd is not null or e.says_yes or e.says_already_done or e.is_name_only)
              and not e.says_no)
    end                                                                       as is_done,
    e.done_by,
    case when e.ymd is not null then e.explicit_date else b.candidate_date end as step_date,
    (e.md is not null and e.ymd is null)                                      as year_was_inferred,
    case when e.kind = 'decision' then
        case when e.raw_text ~ '一个续一个不续'        then 'mixed'
             when e.raw_text ~ '不续|^否'             then 'not_renewing'
             when e.raw_text ~ '续|^是'               then 'renewing'
             else 'unclear' end
    end                                                                       as decision
from explicit_dates e
left join best b using (case_id, step_code)
