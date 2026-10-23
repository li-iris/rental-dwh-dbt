{{ config(severity='warn') }}
-- Warning only: no lease dates could be read from the term column.
select address_raw, tenant_name, term_raw
from {{ ref('stg_tenancy') }}
where lease_start is null
