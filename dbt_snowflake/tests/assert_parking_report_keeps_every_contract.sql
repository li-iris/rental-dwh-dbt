-- The joins in the report must not drop or duplicate contracts.
select 1
where (select count(*) from {{ ref('rpt_parking_contracts') }}) <> (select count(*) from {{ ref('stg_parking_lease') }})
