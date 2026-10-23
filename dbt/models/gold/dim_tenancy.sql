-- One row per tenant per lease. The same lease can appear in several workbook versions;
-- the row from the newest version (see seed source_snapshot_order) wins.
-- Contact details are not part of this model (they stay in bronze only).

with keyed as (
    select
        t.*,
        s.snapshot_rank,
        md5(coalesce(t.property_key, '') || '|' || lower(t.tenant_name) || '|'
            || coalesce(t.lease_start::text, 'unknown'))                as tenancy_id
    from {{ ref('stg_tenancy') }} t
    join {{ ref('source_snapshot_order') }} s
      on s.source_file = t.source_file
),

ranked as (
    select
        *,
        row_number() over (
            partition by tenancy_id
            order by snapshot_rank desc, source_row_number desc
        )                                                               as rn,
        -- first row of each workbook version for this lease = counts the versions it appears in
        row_number() over (
            partition by tenancy_id, snapshot_rank
            order by source_row_number
        )                                                               as rn_in_version
    from keyed
),

counted as (
    select
        *,
        sum(case when rn_in_version = 1 then 1 else 0 end) over (partition by tenancy_id) as snapshot_count
    from ranked
)

select
    tenancy_id,
    md5(property_key)                 as property_id,
    tenant_name,
    is_principal_tenant,
    lease_type,
    lease_start,
    lease_end,
    dates_written_reversed,
    rent_pattern,
    unit_weekly_rent,
    tenant_weekly_share,
    rent_range_high,
    visa_expiry_date,
    source_file,
    snapshot_rank,
    snapshot_count
from counted
where rn = 1
