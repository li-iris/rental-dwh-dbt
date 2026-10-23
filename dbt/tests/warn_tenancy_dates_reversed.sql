{{ config(severity='warn') }}
-- Warning only: the end date was written before the start date in the source (we sort them).
select address_raw, tenant_name, term_raw, lease_start, lease_end
from {{ ref('stg_tenancy') }}
where dates_written_reversed
