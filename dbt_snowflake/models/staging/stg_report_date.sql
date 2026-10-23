-- The day all statuses were judged against when the local warehouse was built.
select report_date from {{ source('raw', 'dim_report_date') }}
