{% macro parking_address_standard(col) -%}
(
    select case when m is not null then m[2] || ' ' || btrim(m[1]) end
    from (
        select regexp_match(
            btrim(translate({{ col }}, '，', ',')),
            '^([A-Za-z][A-Za-z ]*[A-Za-z])\s*,?\s*([0-9]+[A-Za-z]?(?:/[0-9]+[A-Za-z]?)?)'
        ) as m
    ) x
)
{%- endmacro %}
