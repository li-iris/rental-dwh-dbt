"""
Step 2 - Load the Bronze CSVs into Postgres (schema "bronze").

Design rules:
  * One table per LOGICAL sheet. The same sheet from an old and a new workbook
    version goes into the SAME table; _source_file / _file_sha256 tell them apart.
  * Every data column is TEXT (columns are c_a, c_b, ... = Excel letters).
    Blank cells become NULL. Nothing is cleaned here (that is Silver's job).
  * Idempotent: loading the same file twice never creates duplicates. Before a
    file is loaded, rows with the same (file hash, sheet) are deleted, inside the
    same transaction. A changed workbook has a new hash, so it is added as a new
    snapshot and the old snapshot stays.
  * Data minimisation: sheets holding passwords / tenant blacklist are NOT loaded.
  * Uses the `psql` command line tool, so no extra Python package is needed.

Usage:  python scripts/02_load_bronze.py raw_private/bronze_csv [database]
"""
import os
import csv
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

DEFAULT_DB = os.environ.get("RENTAL_DB") or os.environ.get("PGDATABASE") or "rental_dwh"

# sheet title (stripped) -> bronze table name
SHEET_TO_TABLE = {
    "Profit": "profit_monthly",
    "搬家工作记录": "moving_jobs",
    "房租cash": "rent_cash",
    "rent credit": "rent_credit",
    "人民币入账": "rmb_receipts",
    "所有房子入账核对": "rent_reconciliation",
    "0.Tenant": "tenant_list",
    "1.招租+入住+退租list": "tenancy_lifecycle",
    "2.办理租房手续list": "rental_application",
    "2.1房子特别条款&情况登记": "special_terms",
    "2. 财务日常入账": "bank_ledger_coverage",
    "3.转合同-变更信息表格": "contract_transfer",
    "4.办理续租Rental review list": "rent_review",
    "5.1查房和消防通知": "inspection_notice",
    "5.2电和煤气bill结算": "utility_bill",
    "5.3水费结算": "water_bill",
    "车库车位信息表": "garage_parking",
    "房子物品list": "property_items",
}
# Deliberately not loaded (credentials / personal judgements about tenants)
EXCLUDED_SHEETS = {"网络电钥匙管理", "租客黑名单"}

META_COLS = ["_source_file", "_file_sha256", "_sheet", "_row_number"]


def run_psql(db, statements, data=None, capture=False):
    """Run SQL statements through psql in ONE transaction (-1).

    `data` (bytes) is fed to psql's stdin, which is where a
    `COPY ... FROM STDIN` statement reads the CSV rows from.
    """
    cmd = ["psql", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-1", "-d", db]
    if capture:
        cmd += ["-At", "-F", "|"]
    for s in statements:
        cmd += ["-c", s]
    res = subprocess.run(cmd, input=data if data is not None else b"", capture_output=True)
    if res.returncode != 0:
        sys.exit("psql failed:\n" + res.stderr.decode("utf-8", "replace"))
    return res.stdout.decode("utf-8", "replace")


def letters(n: int):
    """1 -> A, 26 -> Z, 27 -> AA ... (same naming as Excel columns)."""
    out = []
    for i in range(1, n + 1):
        s, k = "", i
        while k:
            k, r = divmod(k - 1, 26)
            s = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"[r] + s
        out.append(s)
    return out


def col_name(header: str) -> str:
    return header if header.startswith("_") else "c_" + header.lower()


def sql_str(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def read_csv_info(path: Path):
    with open(path, newline="", encoding="utf-8-sig") as f:
        reader = csv.reader(f)
        header = next(reader)
        first = next(reader, None)
        n = 1 if first else 0
        n += sum(1 for _ in reader)
    if not first:
        return None
    meta = dict(zip(header, first))
    return {
        "path": path,
        "header": header,
        "source_file": meta["_source_file"],
        "sha": meta["_file_sha256"],
        "sheet": meta["_sheet"],
        "rows": n,
        "width": len(header) - len(META_COLS),
    }


def main(csv_dir: str, db: str) -> None:
    folder = Path(csv_dir)
    paths = sorted(p for p in folder.glob("*.csv") if p.name != "_inventory.csv")
    if not paths:
        sys.exit(f"No CSV files in {folder}. Run 01_extract_to_csv.py first.")

    loads, skipped, unknown = [], [], []
    for p in paths:
        info = read_csv_info(p)
        if info is None:
            continue
        title = info["sheet"].strip()
        if title in EXCLUDED_SHEETS:
            skipped.append(info)
        elif title in SHEET_TO_TABLE:
            info["table"] = SHEET_TO_TABLE[title]
            loads.append(info)
        else:
            unknown.append(info)

    if unknown:
        names = ", ".join(sorted({u["sheet"] for u in unknown}))
        sys.exit(f"Sheets with no table mapping (add them to SHEET_TO_TABLE): {names}")

    # 1. Create schema + tables (+ any missing columns). Safe to repeat.
    width_by_table = defaultdict(int)
    for it in loads:
        width_by_table[it["table"]] = max(width_by_table[it["table"]], it["width"])
    ddl = ["CREATE SCHEMA IF NOT EXISTS bronze;"]
    for table, width in sorted(width_by_table.items()):
        ddl.append(
            f"CREATE TABLE IF NOT EXISTS bronze.{table} ("
            "_source_file text, _file_sha256 text, _sheet text, _row_number integer, "
            "_loaded_at timestamptz DEFAULT now());"
        )
    # add columns c_a, c_b, ... in Excel-letter order for each table
    for table, width in sorted(width_by_table.items()):
        for L in letters(width):
            ddl.append(f"ALTER TABLE bronze.{table} ADD COLUMN IF NOT EXISTS c_{L.lower()} text;")
    run_psql(db, ["\n".join(ddl)])

    # 2. Load each CSV: delete same (hash, sheet) rows, then COPY. One transaction per file.
    for it in loads:
        cols = ", ".join(col_name(h) for h in it["header"])
        raw = Path(it["path"]).read_bytes().lstrip(b"\xef\xbb\xbf")
        if not raw.endswith(b"\n"):
            raw += b"\n"
        delete_sql = (
            f"DELETE FROM bronze.{it['table']} WHERE _file_sha256 = {sql_str(it['sha'])} "
            f"AND _sheet = {sql_str(it['sheet'])}"
        )
        copy_sql = (
            f"COPY bronze.{it['table']} ({cols}) FROM STDIN "
            "WITH (FORMAT csv, HEADER true)"
        )
        run_psql(db, [delete_sql, copy_sql], data=raw)

    # 3. Verify: rows in the database must equal rows in the CSV files
    expected = defaultdict(int)
    for it in loads:
        expected[(it["table"], it["sha"], it["sheet"])] += it["rows"]
    parts = [
        f"SELECT '{t}', _file_sha256, _sheet, count(*) FROM bronze.{t} GROUP BY 2, 3"
        for t in sorted(width_by_table)
    ]
    out = run_psql(db, [" UNION ALL ".join(parts)], capture=True)
    actual = {}
    for line in out.strip().splitlines():
        t, sha, sheet, n = line.split("|")
        actual[(t, sha, sheet)] = int(n)

    bad = [(k, expected[k], actual.get(k, 0)) for k in expected if expected[k] != actual.get(k, 0)]
    extra = [k for k in actual if k not in expected]
    print(f"Loaded {len(loads)} CSV files into {len(width_by_table)} bronze tables "
          f"({sum(expected.values())} rows).")
    for info in skipped:
        print(f"  skipped on purpose: {info['sheet'].strip()} ({info['rows']} rows, {info['source_file']})")
    if bad or extra:
        print("MISMATCH:", bad, extra)
        sys.exit(1)
    print("Check passed: database row counts equal CSV row counts.")

    per_table = defaultdict(lambda: [0, 0])
    for (t, sha, sheet), n in actual.items():
        per_table[t][0] += n
        per_table[t][1] += 1
    for t, (n, versions) in sorted(per_table.items()):
        print(f"  bronze.{t:22s} {n:5d} rows  ({versions} source version{'s' if versions > 1 else ''})")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "raw_private/bronze_csv",
         sys.argv[2] if len(sys.argv) > 2 else DEFAULT_DB)
