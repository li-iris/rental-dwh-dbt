{% macro to_date_iso(col) -%}
case when {{ col }} ~ '^\d{4}-\d{2}-\d{2}' then left({{ col }}, 10)::date end
{%- endmacro %}
