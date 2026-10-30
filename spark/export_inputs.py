"""Export what the Spark layer needs from the local PostgreSQL warehouse, as CSV files:

    PGDATABASE=rental_dwh python spark/export_inputs.py raw_private/spark_csv

    <folder>/inputs/<gold table>.csv       the gold tables Spark recomputes the reports from
    <folder>/reference/<report>.csv        the PostgreSQL / dbt answer for each report, to reconcile against

Columns and types come from spark/report_schemas.py. The same two safety checks as scripts/export_gold.py apply
(it is reused, not copied): PGDATABASE must be set explicitly, and the bronze data must come from the synthetic
demo workbooks only - otherwise nothing is exported.
"""
import importlib.util
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import report_schemas as rs  # noqa: E402


def _load_export_gold():
    spec = importlib.util.spec_from_file_location("export_gold", HERE.parent / "scripts" / "export_gold.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


eg = _load_export_gold()


def reference_source(reference, gold: str) -> str:
    """FROM clause for a report's PostgreSQL answer: the dbt table itself, or a query file run on the gold schema."""
    kind, name = reference
    if kind == "table":
        return f"{gold}.{eg.safe_name(name)}"
    if kind == "sql":
        sql = (HERE / "reference_sql" / name).read_text().replace("{gold}", gold).strip().rstrip(";")
        return f"(\n{sql}\n)"
    raise ValueError(f"unknown reference kind {kind!r}")


def jobs(gold: str):
    """(sub folder, file stem, query) for every file to export."""
    out = [("inputs", t, rs.export_query(cols, f"{gold}.{eg.safe_name(t)}")) for t, cols in rs.INPUTS.items()]
    for name, rep in rs.REPORTS.items():
        out.append(("reference", name, rs.export_query(rep["columns"], reference_source(rep["reference"], gold))))
    return out


def main(argv) -> int:
    if len(argv) != 1:
        print(__doc__)
        return 1
    db = os.environ.get("PGDATABASE")
    if not db:
        print("Set PGDATABASE explicitly, e.g.  PGDATABASE=rental_dwh python spark/export_inputs.py ...", file=sys.stderr)
        return 1
    gold = eg.safe_name(os.environ.get("GOLD_SCHEMA", "gold"))
    bronze = eg.safe_name(os.environ.get("BRONZE_SCHEMA", "bronze"))

    files = eg.psql(db, "-At", "-c", f"select distinct _source_file from {bronze}.tenant_list").splitlines()
    if not eg.only_synthetic(files):
        print(f"REFUSED: database {db} has bronze data that is not from the synthetic demo workbooks. "
              "Nothing was exported.", file=sys.stderr)
        return 2

    out = Path(argv[0])
    for sub, stem, query in jobs(gold):
        csv_text = eg.psql(db, "-c", f"copy ({query}) to stdout with (format csv, header true)")
        target = out / sub / f"{stem}.csv"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(csv_text, encoding="utf-8", newline="")
        print(f"{sub}/{stem}.csv: {max(csv_text.count(chr(10)) - 1, 0)} lines after the header")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
