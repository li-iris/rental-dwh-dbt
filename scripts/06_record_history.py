"""Write one run to the history schema: test counts, row counts of every gold table, problems per check, and the
state of water bills and parking contracts. Called by run_all.sh after dbt test.

Usage:  python scripts/06_record_history.py PASS WARN ERROR [note]
"""
import os
import sys

import psycopg

DB = "dbname=" + (os.environ.get("RENTAL_DB") or os.environ.get("PGDATABASE") or "rental_dwh")


def main():
    p, w, e = (int(x) for x in sys.argv[1:4])
    note = sys.argv[4] if len(sys.argv) > 4 else None
    with psycopg.connect(DB) as conn, conn.cursor() as cur:
        cur.execute("select report_date from gold.dim_report_date")
        report_date = cur.fetchone()[0]
        cur.execute("insert into history.run_log(report_date, dbt_pass, dbt_warn, dbt_error, note) values (%s,%s,%s,%s,%s) returning run_id",
                    (report_date, p, w, e, note))
        run_id = cur.fetchone()[0]

        cur.execute("select table_name from information_schema.tables where table_schema = 'gold' and table_type = 'BASE TABLE' order by 1")
        names = [r[0] for r in cur.fetchall()]
        for t in names:
            cur.execute(f'select count(*) from gold."{t}"')
            n = cur.fetchone()[0]
            cur.execute("insert into history.table_rowcount values (%s,%s,%s)", (run_id, t, n))

        cur.execute("select table_schema, table_name from information_schema.tables where table_schema like '%%dbt_test__audit%%' and table_name ~ '^(warn|assert)_'")
        for schema, t in cur.fetchall():
            cur.execute(f'select count(*) from "{schema}"."{t}"')
            n = cur.fetchone()[0]
            cur.execute("insert into history.problem_count values (%s,%s,%s)", (run_id, t, n))

        cur.execute("""insert into history.water_bill_status
                       select %s, water_bill_id, address_raw, amount, follow_up_status, days_past_due from gold.fact_water_bill""", (run_id,))
        cur.execute("""insert into history.parking_status
                       select %s, parking_lease_id, address_raw, contract_status, contract_end_date from gold.fact_parking_lease""", (run_id,))
        conn.commit()
    print(f"History recorded as run {run_id} (report date {report_date}).")


if __name__ == "__main__":
    main()
