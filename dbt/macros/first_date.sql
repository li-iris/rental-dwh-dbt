{% macro first_date(col) -%}
(
    select case
             when m[1] is not null then make_date(m[1]::int, m[2]::int, m[3]::int)   -- 2026.2.9
             when m[4] is not null then make_date(m[4]::int, m[5]::int, m[6]::int)   -- 2026-02-10
             else make_date(m[9]::int, m[8]::int, m[7]::int)                         -- 9/2/2026 (day first)
           end
    from (
        select regexp_match({{ col }},
            '(20[0-9]{2})\.(0?[1-9]|1[0-2])\.(0?[1-9]|[12][0-9]|3[01])|(20[0-9]{2})-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])|(0?[1-9]|[12][0-9]|3[01])/(0?[1-9]|1[0-2])/(20[0-9]{2})'
        ) as m
    ) x
    where m is not null
)
{%- endmacro %}
