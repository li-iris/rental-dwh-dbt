"""Export the finished gold tables of the local PostgreSQL warehouse to CSV files, for the cloud (Snowflake) layer.

    PGDATABASE=demo_dwh python scripts/export_gold.py raw_private/gold_csv

Writes one CSV per table plus _schema.json (column names and Snowflake column types, taken from PostgreSQL).

Two safety checks, because this data leaves the computer:
  1. PGDATABASE must be set explicitly (there is no default database).
  2. The bronze data must come from the synthetic demo workbooks only (file names start with Sample_working_list).
     If any other source file is found, the export refuses to run.
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

PUBLISHED = ["dim_property", "dim_report_date", "fact_water_bill", "fact_parking_lease"]
SYNTHETIC_PREFIX = "Sample_working_list"


def snowflake_type(data_type: str, precision=None, scale=None) -> str:
    t = data_type.lower()
    if t in ("integer", "smallint", "bigint"):
        return "NUMBER(38,0)"
    if t == "numeric":
        p = min(int(precision), 38) if precision else 38
        s = int(scale) if scale not in (None, "") else 6
        return f"NUMBER({p},{s})"
    if t in ("real", "double precision"):
        return "FLOAT"
    if t == "boolean":
        return "BOOLEAN"
    if t == "date":
        return "DATE"
    if t.startswith("timestamp"):
        return "TIMESTAMP_NTZ"
    return "VARCHAR"


def only_synthetic(source_files) -> bool:
    """True when every source file name belongs to the synthetic demo workbooks (and there is at least one)."""
    names = [n for n in source_files if n]
    return bool(names) and all(n.startswith(SYNTHETIC_PREFIX) for n in names)


def safe_name(name: str) -> str:
    if not re.fullmatch(r"[a-z_][a-z_0-9]*", name):
        raise ValueError(f"unsafe identifier: {name!r}")
    return name


def psql(db, *args):
    res = subprocess.run(["psql", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-d", db, *args], capture_output=True, text=True)
    if res.returncode != 0:
        sys.exit("psql failed:\n" + res.stderr)
    return res.stdout


def main(argv) -> int:
    if len(argv) != 1:
        print(__doc__)
        return 1
    db = os.environ.get("PGDATABASE")
    if not db:
        print("Set PGDATABASE explicitly, e.g.  PGDATABASE=demo_dwh python scripts/export_gold.py ...", file=sys.stderr)
        return 1
    gold = safe_name(os.environ.get("GOLD_SCHEMA", "gold"))
    bronze = safe_name(os.environ.get("BRONZE_SCHEMA", "bronze"))

    files = psql(db, "-At", "-c", f"select distinct _source_file from {bronze}.tenant_list").splitlines()
    if not only_synthetic(files):
        print(f"REFUSED: database {db} has bronze data that is not from the synthetic demo workbooks. "
              "Nothing was exported.", file=sys.stderr)
        return 2

    out = Path(argv[0])
    out.mkdir(parents=True, exist_ok=True)
    schema = {}
    for table in PUBLISHED:
        rows = psql(db, "-At", "-F", "|", "-c",
                    "select column_name, data_type, numeric_precision, numeric_scale from information_schema.columns "
                    f"where table_schema = '{gold}' and table_name = '{safe_name(table)}' order by ordinal_position").splitlines()
        if not rows:
            print(f"table {gold}.{table} not found - run the pipeline first (make demo)", file=sys.stderr)
            return 1
        cols = []
        for line in rows:
            name, dtype, prec, scale = line.split("|")
            cols.append({"name": name, "type": snowflake_type(dtype, prec, scale)})
        schema[table] = cols
        target = (out / f"{table}.csv").resolve()
        psql(db, "-c", f"\\copy (select * from {gold}.{table}) to '{target}' with (format csv, header true)")
        print(f"{table}: {len(cols)} columns -> {target.name}")
    (out / "_schema.json").write_text(json.dumps(schema, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
