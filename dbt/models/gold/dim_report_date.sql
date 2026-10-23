{{ config(materialized='view') }}
-- One row: the "as of" date every overdue / expired / due-soon status is judged against.
-- Default = the day dbt runs. To look at the data as of an earlier day:  dbt run --vars '{report_date: 2026-01-13}'
-- Kept separate from fact_turnover_step so that other facts still work when there is no turnover data.
{% set rd = var('report_date', '') %}
select
    {% if rd %} '{{ rd }}'::date {% else %} current_date {% endif %} as report_date
