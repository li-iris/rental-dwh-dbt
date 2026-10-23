{# Looks up a number from the seed business_rules, e.g. {{ rule('water_invoice_due_days') }}. Edit the CSV, not the models. #}
{% macro rule(rule_id) -%}
(select value::numeric from {{ ref('business_rules') }} where rule_id = '{{ rule_id }}')
{%- endmacro %}

{# Same, as a whole number of days, so it can be added to a date. #}
{% macro rule_days(rule_id) -%}
(select value::int from {{ ref('business_rules') }} where rule_id = '{{ rule_id }}')
{%- endmacro %}
