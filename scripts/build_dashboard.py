"""Build one self-contained HTML dashboard (no server, no JavaScript libraries) from the gold layer.

Usage: python scripts/build_dashboard.py docs_site/dashboard.html
"""
import html
import sys
from datetime import datetime
from pathlib import Path

import psycopg

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else "docs_site/dashboard.html")


def q(cur, sql):
    cur.execute(sql)
    return cur.fetchall()


def bars(rows, title):
    if not rows:
        return f"<h3>{html.escape(title)}</h3><p class=m>no data</p>"
    top = max(v for _, v in rows) or 1
    out = [f"<h3>{html.escape(title)}</h3>"]
    for label, v in rows:
        w = int(100 * v / top)
        out.append(f"<div class=r><span class=l>{html.escape(str(label))}</span>"
                   f"<span class=b><i style='width:{w}%'></i></span><span class=v>{v}</span></div>")
    return "".join(out)


with psycopg.connect("") as conn, conn.cursor() as cur:
    as_of = q(cur, "select report_date from gold.dim_report_date")[0][0]
    kpi = {
        "Properties": q(cur, "select count(*) from gold.dim_property")[0][0],
        "Tenancies": q(cur, "select count(*) from gold.dim_tenancy")[0][0],
        "Water bills": q(cur, "select count(*) from gold.fact_water_bill")[0][0],
        "Inspections": q(cur, "select count(*) from gold.fact_inspection_notice")[0][0],
    }
    water = q(cur, "select follow_up_status, count(*) from gold.fact_water_bill group by 1 order by 2 desc")
    parking = q(cur, "select contract_status, count(*) from gold.fact_parking_lease group by 1 order by 2 desc")
    problems = []
    for schema, t in q(cur, "select table_schema, table_name from information_schema.tables where table_schema like '%dbt_test__audit%' and table_name like 'warn\\_%' order by 2"):
        n = q(cur, f'select count(*) from "{schema}"."{t}"')[0][0]
        if n:
            problems.append((t.replace("warn_", "").replace("_", " "), n))
    problems.sort(key=lambda x: -x[1])
    runs = q(cur, "select to_char(started_at,'YYYY-MM-DD HH24:MI'), dbt_pass, dbt_warn, dbt_error from history.run_log order by run_id desc limit 8")

tiles = "".join(f"<div class=t><b>{v}</b><span>{html.escape(k)}</span></div>" for k, v in kpi.items())
runs_html = "".join(f"<tr><td>{a}</td><td>{p}</td><td>{w}</td><td>{e}</td></tr>" for a, p, w, e in runs)
page = f"""<!doctype html><html lang=en><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
<title>Rental DWH dashboard</title>
<style>
:root{{--bg:#fff;--fg:#1d2433;--m:#667085;--b:#2a6df4;--c:#f4f6fa}}
@media(prefers-color-scheme:dark){{:root{{--bg:#12151c;--fg:#e8ebf2;--m:#98a2b3;--b:#6b9bff;--c:#1c2130}}}}
body{{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif}}main{{max-width:900px;margin:auto;padding:24px 16px}}
.g{{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px}}.t{{background:var(--c);border-radius:10px;padding:14px}}
.t b{{display:block;font-size:28px}}.t span,.m{{color:var(--m)}}.r{{display:flex;align-items:center;gap:8px;margin:4px 0}}
.l{{width:240px;max-width:45%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}}.b{{flex:1;background:var(--c);height:12px;border-radius:6px}}
.b i{{display:block;height:100%;background:var(--b);border-radius:6px}}.v{{width:40px;text-align:right}}
table{{border-collapse:collapse;width:100%}}td,th{{padding:4px 8px;text-align:left;border-bottom:1px solid var(--c)}}
</style><main>
<h1>Rental warehouse - status</h1>
<p class=m>Synthetic demo data. Statuses judged as of {as_of}. Built {datetime.now():%Y-%m-%d %H:%M}.</p>
<div class=g>{tiles}</div>
{bars(water, "Water bills by follow-up status")}
{bars(parking, "Parking contracts by status")}
{bars(problems, "Open follow-ups by check (WARN tests)")}
<h3>Recent runs</h3><table><tr><th>Started</th><th>Pass</th><th>Warn</th><th>Error</th></tr>{runs_html}</table>
</main></html>"""
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(page, encoding="utf-8")
print("wrote", OUT)
