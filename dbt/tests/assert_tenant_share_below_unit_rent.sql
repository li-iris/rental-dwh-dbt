-- Fails if a tenant's own share is not smaller than the rent of the whole unit.
select address_raw, tenant_name, unit_weekly_rent, tenant_weekly_share
from {{ ref('stg_tenancy') }}
where tenant_weekly_share >= unit_weekly_rent
