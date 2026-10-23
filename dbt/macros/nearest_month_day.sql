{# A cell like "6.18casey" or "12.11 Drew" holds month.day without a year.
   The year is the one that puts the date closest to a reference date (for a bill: the day the company paid it). #}
{% macro nearest_month_day(text_col, ref_date) -%}
(
    select c.d
    from (select regexp_match({{ text_col }}, '(?:^|[^0-9.])([0-9]{1,2})\.([0-9]{1,2})(?:[^0-9]|$)') as m) x
    cross join lateral generate_series(extract(year from {{ ref_date }})::int - 1, extract(year from {{ ref_date }})::int + 1) as y(yr)
    cross join lateral (select (make_date(y.yr, 1, 1) + (x.m[1]::int - 1) * interval '1 month' + (x.m[2]::int - 1) * interval '1 day')::date as d) c
    where x.m is not null and {{ ref_date }} is not null
      and x.m[1]::int between 1 and 12 and x.m[2]::int between 1 and 31
      and extract(month from c.d) = x.m[1]::int
    order by abs(c.d - {{ ref_date }})
    limit 1
)
{%- endmacro %}
