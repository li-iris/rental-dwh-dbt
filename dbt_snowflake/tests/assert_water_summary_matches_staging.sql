-- The summary must account for every water bill exactly once.
select 1
where (select sum(bills) from {{ ref('rpt_water_status_summary') }}) <> (select count(*) from {{ ref('stg_water_bill') }})
