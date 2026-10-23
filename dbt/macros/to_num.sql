{% macro to_num(col) -%}
case when {{ col }} ~ '^-?[0-9]+(\.[0-9]+)?$' then {{ col }}::numeric end
{%- endmacro %}
