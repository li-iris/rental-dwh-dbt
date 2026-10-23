{% macro parse_loose_date(col) -%}
(case
    when {{ col }} ~ '^[0-9]{1,2} [A-Za-z]{3} [0-9]{2,4}$'
        then to_date(regexp_replace({{ col }}, ' ([0-9]{2})$', ' 20\1'), 'DD Mon YYYY')
    when {{ col }} ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$'
        then to_date({{ col }}, 'DD/MM/YYYY')
    when {{ col }} ~ '^[0-9]{4}[./][0-9]{1,2}[./][0-9]{1,2}$'
        then to_date(replace({{ col }}, '.', '/'), 'YYYY/MM/DD')
end)
{%- endmacro %}
