-- One row per calendar day, 2023-01-01 to 2027-12-31. Financial year follows the Australian year (1 July - 30 June).

select
    d::date                                                             as date_day,
    extract(year from d)::int                                           as year,
    extract(quarter from d)::int                                        as quarter,
    extract(month from d)::int                                          as month,
    to_char(d, 'Mon')                                                   as month_name,
    extract(day from d)::int                                            as day_of_month,
    extract(isodow from d)::int                                         as day_of_week,
    to_char(d, 'Dy')                                                    as day_name,
    extract(isodow from d) in (6, 7)                                    as is_weekend,
    date_trunc('week', d)::date                                         as week_start_date,
    date_trunc('month', d)::date                                        as month_start_date,
    case when extract(month from d) >= 7
         then 'FY' || extract(year from d)::int || '-' || right((extract(year from d)::int + 1)::text, 2)
         else 'FY' || (extract(year from d)::int - 1) || '-' || right(extract(year from d)::int::text, 2)
    end                                                                 as financial_year
from generate_series('2023-01-01'::date, '2027-12-31'::date, interval '1 day') as g(d)
