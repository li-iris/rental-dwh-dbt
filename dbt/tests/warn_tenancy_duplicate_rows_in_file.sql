{{ config(severity='warn') }}
-- Warning only: the same tenant, property and start date appears more than once inside ONE workbook.
select source_file, property_key, lower(tenant_name) as tenant_name_lower,
       coalesce(lease_start::text, 'unknown') as lease_start, count(*) as rows_found
from {{ ref('stg_tenancy') }}
group by 1, 2, 3, 4
having count(*) > 1
