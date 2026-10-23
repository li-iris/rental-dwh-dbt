-- One row per room turnover: old tenant leaves, (maybe) new tenant arrives.

select
    c.case_id,
    p.property_id,
    c.property_key,
    c.address_raw,
    c.turnover_section,
    c.source_file,
    c.old_contract_end_date,
    c.actual_move_out_date,
    c.new_move_in_date,
    -- the move-out date used for deadlines: the actual one if known, otherwise the planned contract end
    coalesce(c.actual_move_out_date, c.old_contract_end_date)                         as move_out_date_used,
    (c.new_move_in_date is not null)                                                   as has_next_tenant,
    -- empty days between the old tenant leaving and the new tenant arriving
    case when c.new_move_in_date is not null
          and coalesce(c.actual_move_out_date, c.old_contract_end_date) is not null
         then c.new_move_in_date - coalesce(c.actual_move_out_date, c.old_contract_end_date)
    end                                                                                as vacancy_gap_days,
    c.listed_rent_raw,
    c.actual_rent_raw
from {{ ref('stg_turnover_case') }} c
left join {{ ref('dim_property') }} p
       on p.property_key = c.property_key
