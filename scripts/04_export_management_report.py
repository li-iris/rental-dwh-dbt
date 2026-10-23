"""Export a management report from the gold layer to an Excel workbook.

Sheets: water bills to collect, inspections, lease expiry, rent vs recorded money, rent that is unclear,
paperwork gaps, special clauses, questions for the owner.
Reads gold.* tables and writes reports/management_report.xlsx.
The report is for internal use (it contains real addresses and tenant names), so reports/ is git-ignored.

"As of" date: gold.fact_turnover_step.report_date, which is the day dbt last ran unless a date was set with
--vars report_date. Everything that depends on today's date (lease expiry, inspections) is judged against it.

Run:  python scripts/04_export_management_report.py
"""
import os
import datetime
from pathlib import Path

import psycopg
from openpyxl import Workbook
from openpyxl.formatting.rule import FormulaRule
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter

DB = "dbname=" + (os.environ.get("RENTAL_DB") or os.environ.get("PGDATABASE") or "rental_dwh")
OUT = Path(__file__).resolve().parent.parent / "reports" / "management_report.xlsx"

HEADER_FILL = PatternFill("solid", fgColor="1F3864")
HEADER_FONT = Font(bold=True, color="FFFFFF")
RED = PatternFill("solid", fgColor="F8CBAD")
AMBER = PatternFill("solid", fgColor="FFE699")
GREY = PatternFill("solid", fgColor="EDEDED")
MONEY = '#,##0.00'

PROCESS_LABEL = {
    "rental_application": "New tenant paperwork",
    "rent_review": "Lease renewal",
    "contract_transfer": "Contract transfer",
}
NOTICE_LABEL = {"routine": "Routine inspection", "fire": "Fire safety inspection", "other": "Other notice"}
BASIS_LABEL = {
    "unit_rent": "Whole-unit rent",
    "room_rent": "Single room rent",
    "room_rents_estimated": "Several room rents added up (estimate)",
    "rent_type_changed_in_month": "Rent type changed during the month",
    "unclear": "Unclear - left empty",
    "no_tenancy": "No tenancy covers this month",
}
WATER_LABEL = {
    "invoice_overdue": "Invoice overdue - company paid, no invoice recorded",
    "payment_overdue": "Payment overdue - invoice sent, no tenant payment recorded",
    "invoice_due_soon": "Invoice due soon",
    "awaiting_payment": "Invoice sent, waiting for payment",
    "payment_date_unknown": "Invoice sent, date unknown",
}
RULE_LABEL = {
    "unit_rent_replaces_room_rents": "Whole-unit rent used instead of room rents",
    "newest_unit_rent_used": "Newest whole-unit rent used",
    "lease_without_rent_ignored": "Lease without a rent ignored",
}
REASON_LABEL = {
    "rent_missing": "A rent is missing",
    "unit_and_room_rents_mixed": "Whole-unit rent next to room rents",
    "different_unit_rents": "Two different whole-unit rents",
}


def fetch(cur, sql):
    cur.execute(sql)
    cols = [d.name for d in cur.description]
    return [dict(zip(cols, r)) for r in cur.fetchall()]


def num(v):
    return None if v is None else float(v)


def write_table(ws, headers, rows, widths, money_cols=(), start_row=1):
    """Header row plus data rows; returns the last row number. money_cols are 1-based column numbers."""
    for j, h in enumerate(headers, start=1):
        c = ws.cell(row=start_row, column=j, value=h)
        c.fill, c.font = HEADER_FILL, HEADER_FONT
        c.alignment = Alignment(wrap_text=True, vertical="center")
    for i, row in enumerate(rows, start=start_row + 1):
        for j, v in enumerate(row, start=1):
            c = ws.cell(row=i, column=j, value=v)
            if isinstance(v, datetime.date):
                c.number_format = "yyyy-mm-dd"
            elif j in money_cols and v is not None:
                c.number_format = MONEY
            c.alignment = Alignment(vertical="top", wrap_text=True)
    for j, w in enumerate(widths, start=1):
        ws.column_dimensions[get_column_letter(j)].width = w
    last = start_row + len(rows)
    ws.freeze_panes = ws.cell(row=start_row + 1, column=2)
    if rows:
        ws.auto_filter.ref = f"A{start_row}:{get_column_letter(len(headers))}{last}"
    return max(last, start_row + 1)      # an empty table must still give a valid range for the conditional formats


def main():
    with psycopg.connect(DB) as conn, conn.cursor() as cur:
        as_of = fetch(cur, "select report_date as d from gold.dim_report_date")[0]["d"]
        d = f"date '{as_of:%Y-%m-%d}'"

        water = fetch(cur, """
            select coalesce(p.master_address_raw, p.property_key) as address, w.period_text, w.amount,
                   w.company_paid_date, w.invoice_sent_date, w.invoice_sent_by, w.follow_up_status, w.days_past_due,
                   w.invoice_text, w.tenant_paid_text
            from gold.fact_water_bill w
            left join gold.dim_property p on p.property_id = w.property_id
            where w.follow_up_status not in ('closed', 'company_not_paid_yet')
            order by case w.follow_up_status when 'invoice_overdue' then 1 when 'payment_overdue' then 2 else 3 end,
                     w.days_past_due desc nulls last, address, w.period_start
        """)

        inspections = fetch(cur, f"""
            select n.notice_type, coalesce(p.master_address_raw, p.property_key, n.address_raw) as address,
                   n.notice_date, n.time_text, n.notice_sent, n.sent_by, n.pre_check_text, n.pre_check_by,
                   n.attended_by, n.completion_text, n.category, n.follow_up_by,
                   concat_ws('; ',
                       case when n.notice_date is null then 'Date not readable' end,
                       case when not n.notice_sent then 'Notice not recorded as sent' end,
                       case when n.notice_type in ('fire', 'other') and n.completion_text is null
                            then 'Completion not recorded' end,
                       case when n.property_id is null then 'Address is not a managed property' end) as issues
            from gold.fact_inspection_notice n
            left join gold.dim_property p on p.property_id = n.property_id
            where n.notice_date between {d} - 60 and {d} + 60
            order by n.notice_date, address
        """)

        warn_days = int(fetch(cur, "select value from gold.dim_business_rule where rule_id = 'lease_expiry_warning_days'")[0]["value"])

        leases = fetch(cur, f"""
            select coalesce(p.master_address_raw, p.property_key) as address, t.tenant_name, t.is_principal_tenant,
                   t.lease_type, t.lease_start, t.lease_end, t.lease_end - {d} as days_left,
                   t.unit_weekly_rent,
                   exists (select 1 from gold.fact_process_case c
                           where c.property_id = t.property_id and c.process = 'rent_review'
                             and not c.is_cancelled
                             and abs(coalesce(c.contract_end_date, c.anchor_date) - t.lease_end) <= 14) as renewal_started
            from gold.dim_tenancy t
            join gold.dim_property p on p.property_id = t.property_id
            where t.lease_end between {d} - 30 and {d} + {warn_days} and not t.dates_written_reversed
            order by t.lease_end, address, t.tenant_name
        """)

        rent = fetch(cur, """
            select coalesce(p.master_address_raw, p.property_key) as address, r.month_start, r.rent_basis,
                   r.expected_rent_aud, r.cash_received_aud, r.rmb_received_aud, r.vacancy_credit_aud,
                   r.recorded_minus_expected_aud
            from gold.fact_rent_roll_month r
            join gold.dim_property p on p.property_id = r.property_id
            where r.has_recorded_payment
            order by abs(coalesce(r.recorded_minus_expected_aud, 0)) desc, address, r.month_start
        """)
        rent_months = fetch(cur, """
            select to_char(month_start, 'YYYY-MM') as month, count(*) as properties,
                   count(*) filter (where expected_rent_aud is not null) as with_expected_rent,
                   count(*) filter (where rent_basis = 'unclear') as unclear,
                   sum(expected_rent_aud) as expected_total
            from gold.fact_rent_roll_month
            where rent_basis <> 'no_tenancy'
            group by month_start order by month_start
        """)
        unclear = fetch(cur, """
            select coalesce(p.master_address_raw, p.property_key) as address,
                   string_agg(distinct r.unclear_reason, ', ') as reasons,
                   count(*) as months,
                   string_agg(distinct r.rent_rules_applied, ', ') as rules_applied,
                   round(avg(r.expected_rent_with_rules_aud), 2) as monthly_with_rules,
                   (select string_agg(distinct t.unit_weekly_rent::text, ' / ' order by t.unit_weekly_rent::text)
                      from gold.dim_tenancy t
                     where t.property_id = r.property_id
                       and t.lease_end >= date '2025-07-01' and t.lease_start <= date '2026-01-31') as rents_in_tenancy_list
            from gold.fact_rent_roll_month r
            join gold.dim_property p on p.property_id = r.property_id
            where r.rent_basis = 'unclear'
            group by r.property_id, address
            order by months desc, address
        """)

        paperwork = fetch(cur, f"""
            select c.process, coalesce(p.master_address_raw, p.property_key, c.address_raw) as address,
                   c.case_type, c.anchor_date,
                   count(*) filter (where f.entry_type <> 'not_applicable') as steps_that_apply,
                   count(*) filter (where f.is_done) as steps_done,
                   count(*) filter (where f.is_missing) as steps_missing,
                   string_agg(s.step_name, '; ' order by s.step_order) filter (where f.is_missing) as missing_steps
            from gold.fact_process_case c
            join gold.fact_process_step f on f.case_id = c.case_id
            join gold.dim_process_step s on s.process = f.process and s.step_code = f.step_code
            left join gold.dim_property p on p.property_id = c.property_id
            where not c.is_cancelled and c.anchor_date >= {d} - 120
            group by c.case_id, c.process, address, c.case_type, c.anchor_date
            having count(*) filter (where f.is_missing) > 0
            order by steps_missing desc, c.anchor_date desc
        """)

        clauses = fetch(cur, """
            select coalesce(p.master_address_raw, p.property_key, t.address_raw) as address,
                   t.term_text, t.status_text, t.recorded_by, t.recorded_text
            from gold.fact_special_term t
            left join gold.dim_property p on p.property_id = t.property_id
            order by t.has_status, address
        """)

        counts = {
            "water_total": sum(float(r["amount"] or 0) for r in water),
        }

    wb = Workbook()

    # ---- About
    ws = wb.active
    ws.title = "About"
    not_sent = sum(1 for r in water if r["follow_up_status"] == "invoice_overdue")
    lines = [
        ("Management report", True),
        (f"Status as of: {as_of:%d %b %Y} (the day dbt last ran, or the date set with --vars report_date)", False),
        ("", False),
        ("What is in this workbook", True),
        (f"Water bills to collect: {len(water)} bills, ${counts['water_total']:,.2f} in total "
         f"({not_sent} invoices overdue, {sum(1 for r in water if r['follow_up_status'] == 'payment_overdue')} payments overdue; "
         f"the due days are set in the seed business_rules).", False),
        (f"Inspections: {len(inspections)} inspections or notices within 60 days of the status date.", False),
        (f"Lease expiry: {len(leases)} tenancies ending between 30 days before and {warn_days} days after the status date (rule lease_expiry_warning_days).", False),
        (f"Rent vs recorded: {len(rent)} property-months with a recorded payment or credit.", False),
        (f"Rent unclear: {len(unclear)} properties whose expected rent cannot be worked out yet.", False),
        (f"Paperwork gaps: {len(paperwork)} recent paperwork cases with steps nobody recorded.", False),
        (f"Special clauses: {len(clauses)} clauses, {sum(1 for r in clauses if not r['status_text'])} with no 'carried out' note.", False),
        ("", False),
        ("How to read it", True),
        ("A blank cell in the working list may mean the step was not done, or done but not written down. This report cannot tell the difference.", False),
        ("Expected rent: a weekly rent of 600 or less is treated as one room, above 600 as the whole unit. "
         "When the tenancy list does not allow a clear answer the expected rent is left empty on purpose.", False),
        ("The workbooks hold no bank transaction detail. 'No recorded payment' does not mean 'not paid'.", False),
        ("", False),
        ("Caution", True),
        ("This file contains real addresses and tenant names. Do not share it outside the company.", False),
    ]
    for i, (text, bold) in enumerate(lines, start=1):
        c = ws.cell(row=i, column=1, value=text)
        c.font = Font(bold=bold, size=14 if i == 1 else 11)
        c.alignment = Alignment(wrap_text=True, vertical="top")
    ws.column_dimensions["A"].width = 120

    # ---- Water bills to collect
    ws = wb.create_sheet("Water to collect")
    headers = ["Address", "Billing period", "Amount (AUD)", "Company paid", "Invoice sent", "Sent by", "Status",
               "Days past due", "Invoice note", "Tenant payment note"]
    rows = [[r["address"], r["period_text"], num(r["amount"]), r["company_paid_date"], r["invoice_sent_date"],
             r["invoice_sent_by"], WATER_LABEL.get(r["follow_up_status"], r["follow_up_status"]), r["days_past_due"],
             r["invoice_text"], r["tenant_paid_text"]] for r in water]
    last = write_table(ws, headers, rows, [44, 26, 14, 14, 14, 12, 52, 12, 30, 30], money_cols=(3,))
    ws.conditional_formatting.add(f"G2:G{last}", FormulaRule(formula=['LEFT($G2,7)="Invoice"'], fill=AMBER))
    ws.conditional_formatting.add(f"G2:G{last}", FormulaRule(formula=['ISNUMBER(SEARCH("overdue",$G2))'], fill=RED))
    ws.cell(row=last + 2, column=2, value="Total").font = Font(bold=True)
    c = ws.cell(row=last + 2, column=3, value=f"=SUM(C2:C{last})")
    c.number_format, c.font = MONEY, Font(bold=True)

    # ---- Inspections
    ws = wb.create_sheet("Inspections")
    headers = ["Type", "Address", "Date", "Time", "Notice sent", "Sent by", "Pre-check", "Pre-check by",
               "Attended by", "Completion", "Category", "Follow-up by", "To follow up"]
    rows = [[NOTICE_LABEL.get(r["notice_type"], r["notice_type"]), r["address"], r["notice_date"], r["time_text"],
             "Yes" if r["notice_sent"] else "Not recorded", r["sent_by"], r["pre_check_text"], r["pre_check_by"],
             r["attended_by"], r["completion_text"], r["category"], r["follow_up_by"], r["issues"] or None]
            for r in inspections]
    last = write_table(ws, headers, rows, [24, 44, 12, 16, 13, 10, 18, 12, 12, 24, 18, 12, 40])
    ws.conditional_formatting.add(f"M2:M{last}", FormulaRule(formula=['LEN($M2)>0'], fill=AMBER))

    # ---- Lease expiry
    ws = wb.create_sheet("Lease expiry")
    headers = ["Address", "Tenant", "Main tenant", "Lease type", "Lease start", "Lease end", "Days left",
               "Weekly rent as written", "Renewal paperwork started"]
    rows = [[r["address"], r["tenant_name"], "Yes" if r["is_principal_tenant"] else "", r["lease_type"],
             r["lease_start"], r["lease_end"], r["days_left"], num(r["unit_weekly_rent"]),
             "Yes" if r["renewal_started"] else "No"] for r in leases]
    last = write_table(ws, headers, rows, [44, 26, 11, 14, 12, 12, 10, 16, 18], money_cols=(8,))
    ws.conditional_formatting.add(f"G2:G{last}", FormulaRule(formula=["$G2<0"], fill=GREY))
    ws.conditional_formatting.add(f"G2:G{last}", FormulaRule(formula=["AND($G2>=0,$G2<=30)"], fill=RED))
    ws.conditional_formatting.add(f"G2:G{last}", FormulaRule(formula=["AND($G2>30,$G2<=60)"], fill=AMBER))
    ws.conditional_formatting.add(f"I2:I{last}", FormulaRule(formula=['$I2="No"'], fill=AMBER))

    # ---- Rent vs recorded
    ws = wb.create_sheet("Rent vs recorded")
    headers = ["Address", "Month", "How expected rent was worked out", "Expected rent", "Cash received",
               "RMB received (AUD)", "Vacancy credit", "Recorded minus expected"]
    rows = [[r["address"], r["month_start"], BASIS_LABEL.get(r["rent_basis"], r["rent_basis"]),
             num(r["expected_rent_aud"]), num(r["cash_received_aud"]), num(r["rmb_received_aud"]),
             num(r["vacancy_credit_aud"]), num(r["recorded_minus_expected_aud"])] for r in rent]
    last = write_table(ws, headers, rows, [44, 12, 38, 14, 14, 16, 14, 18], money_cols=(4, 5, 6, 7, 8))
    ws.conditional_formatting.add(f"H2:H{last}", FormulaRule(formula=["ABS($H2)>5"], fill=AMBER))
    start = last + 3
    ws.cell(row=start - 1, column=1, value="Expected rent by month (all properties)").font = Font(bold=True, size=12)
    h2 = ["Month", "Properties with a tenancy", "Expected rent could be worked out", "Left empty (unclear)", "Expected rent total"]
    r2 = [[r["month"], r["properties"], r["with_expected_rent"], r["unclear"], num(r["expected_total"])] for r in rent_months]
    for j, h in enumerate(h2, start=1):
        c = ws.cell(row=start, column=j, value=h)
        c.fill, c.font = HEADER_FILL, HEADER_FONT
        c.alignment = Alignment(wrap_text=True)
    for i, row in enumerate(r2, start=start + 1):
        for j, v in enumerate(row, start=1):
            c = ws.cell(row=i, column=j, value=v)
            if j == 5 and v is not None:
                c.number_format = MONEY

    # ---- Rent unclear
    ws = wb.create_sheet("Rent unclear")
    headers = ["Address", "Why unclear", "Months affected", "Weekly rents in the tenancy list",
               "Default rule applied (assumed)", "Monthly rent with the rule (average)", "Correct rent (owner)", "Comment"]
    rows = [[r["address"], ", ".join(REASON_LABEL.get(x, x) for x in (r["reasons"] or "").split(", ") if x),
             r["months"], r["rents_in_tenancy_list"],
             ", ".join(RULE_LABEL.get(x, x) for x in (r["rules_applied"] or "").split(", ") if x) or "None - left empty",
             num(r["monthly_with_rules"]), None, None] for r in unclear]
    write_table(ws, headers, rows, [44, 44, 12, 34, 44, 18, 22, 30], money_cols=(6,))

    # ---- Paperwork gaps
    ws = wb.create_sheet("Paperwork gaps")
    headers = ["Paperwork", "Address", "Case type", "Anchor date", "Steps that apply", "Done", "Nothing recorded", "Steps with nothing recorded"]
    rows = [[PROCESS_LABEL.get(r["process"], r["process"]), r["address"], r["case_type"], r["anchor_date"],
             r["steps_that_apply"], r["steps_done"], r["steps_missing"], r["missing_steps"]] for r in paperwork]
    write_table(ws, headers, rows, [24, 44, 14, 12, 12, 8, 12, 90])

    # ---- Special clauses
    ws = wb.create_sheet("Special clauses")
    headers = ["Address", "Special clause", "Carried out?", "Recorded by", "Recorded (as written)"]
    rows = [[r["address"], r["term_text"], r["status_text"] or "Nothing recorded", r["recorded_by"], r["recorded_text"]]
            for r in clauses]
    last = write_table(ws, headers, rows, [44, 50, 50, 12, 16])
    ws.conditional_formatting.add(f"C2:C{last}", FormulaRule(formula=['$C2="Nothing recorded"'], fill=AMBER))

    OUT.parent.mkdir(exist_ok=True)
    wb.save(OUT)
    print(f"Wrote {OUT}")
    print(f"  water: {len(water)}, inspections: {len(inspections)}, leases: {len(leases)}, rent rows: {len(rent)}, "
          f"rent unclear: {len(unclear)}, paperwork gaps: {len(paperwork)}, clauses: {len(clauses)}")


if __name__ == "__main__":
    main()
