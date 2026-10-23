-- One row per room turnover (move-out and move-in tracking row) from the "1.招租+入住+退租list" sheet.
-- The sheet has section title rows (e.g. "1.xxx") between the data rows; they give each case its status.

with raw_rows as (
    select
        t.*,
        (c_a ~ '^[0-9]+\s*[.、]') as is_section_title
    from {{ source('bronze', 'tenancy_lifecycle') }} t
    where _row_number > 3
      and c_a is not null
),

grouped as (
    select *,
        sum(is_section_title::int) over (partition by _file_sha256 order by _row_number) as section_no
    from raw_rows
),

titled as (
    select *,
        max(case when is_section_title then c_a end) over (partition by _file_sha256, section_no) as section_title_raw
    from grouped
)

select
    md5(t._file_sha256 || '|' || t._row_number::text)                  as case_id,
    t._source_file                                                    as source_file,
    t._file_sha256                                                    as source_file_sha256,
    t._row_number                                                     as source_row_number,
    trim(t.c_a)                                                       as address_raw,
    a.property_key,
    t.section_title_raw,
    case
        when t.section_title_raw ~ '不再招租'       then 'move_out_not_relisted'
        when t.section_title_raw ~ '待招长租'       then 'awaiting_long_term_tenant'
        when t.section_title_raw ~ '招短租'         then 'relisting_short_term'
        when t.section_title_raw ~ '转租'           then 'sublet'
        when t.section_title_raw ~ '长租租客退租'   then 'long_term_to_short_term'
        else 'move_out_new_tenant_found'
    end                                                               as turnover_section,
    trim(t.c_b)                                                       as tenant_note_raw,
    {{ first_date('t.c_c') }}                                         as old_contract_end_date,
    trim(t.c_c)                                                       as old_contract_end_raw,
    {{ first_date('t.c_d') }}                                         as actual_move_out_date,
    trim(t.c_d)                                                       as actual_move_out_raw,
    {{ first_date('t.c_e') }}                                         as new_move_in_date,
    trim(t.c_g)                                                       as listed_rent_raw,
    trim(t.c_h)                                                       as actual_rent_raw
from titled t
left join {{ ref('stg_address_parsed') }} a
       on a.src = 'tenancy_lifecycle'
      and a.address_raw = trim(t.c_a)
where t.c_a ~ '^[0-9]'
  and not t.is_section_title
