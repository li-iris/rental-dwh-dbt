{{ config(severity='warn') }}
-- Warning only: the rent cell has a format we have no rule for. Revenue could be wrong for these rows.
select address_raw, tenant_name, rent_raw
from {{ ref('stg_tenancy') }}
where rent_pattern = 'other'
