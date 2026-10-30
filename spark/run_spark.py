"""Recompute three warehouse reports with Spark, write them as Parquet (partitioned by month) and reconcile each one
row for row against the PostgreSQL / dbt answer exported by spark/export_inputs.py.

    python spark/run_spark.py --master "local[*]" --input raw_private/spark_csv --output raw_private/spark_out

--input / --output can also come from SPARK_INPUT_DIR / SPARK_OUTPUT_DIR and may be any path Spark can read
(a local folder, dbfs:/..., /Volumes/..., s3://...). Without --master (or SPARK_MASTER) the session that already
exists is used, e.g. on Databricks; outside Databricks it falls back to local[*].

Exit code 0 = every report matches; 1 = at least one mismatch (or an empty reference); 2 = wrong arguments.
"""
import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from pyspark.sql import SparkSession  # noqa: E402

import transforms as T  # noqa: E402
from report_schemas import INPUTS, REPORTS, ddl  # noqa: E402

CSV_OPTIONS = {"header": "true", "multiLine": "true", "escape": '"', "mode": "FAILFAST", "dateFormat": "yyyy-MM-dd"}


def session(master):
    builder = SparkSession.builder.appName("rental_dwh_spark")
    if master:
        builder = (builder.master(master)
                   .config("spark.sql.shuffle.partitions", "4")
                   .config("spark.ui.enabled", "false"))
    return builder.config("spark.sql.session.timeZone", "UTC").getOrCreate()


def read_csv(spark, path, columns):
    return spark.read.options(**CSV_OPTIONS).schema(ddl(columns)).csv(path)


def join_path(base, *parts):
    return "/".join([base.rstrip("/"), *parts])


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--input", default=os.environ.get("SPARK_INPUT_DIR"), help="folder written by export_inputs.py")
    p.add_argument("--output", default=os.environ.get("SPARK_OUTPUT_DIR"), help="where the Parquet reports go")
    p.add_argument("--master", default=os.environ.get("SPARK_MASTER"), help='e.g. "local[*]"; omit on Databricks')
    p.add_argument("--allow-empty", action="store_true", help="do not fail when a reference has no rows")
    args = p.parse_args(argv)
    if not args.input or not args.output:
        p.print_usage(sys.stderr)
        print("--input and --output (or SPARK_INPUT_DIR / SPARK_OUTPUT_DIR) are required", file=sys.stderr)
        return 2
    master = args.master or (None if os.environ.get("DATABRICKS_RUNTIME_VERSION") else "local[*]")

    spark = session(master)
    inputs = {name: read_csv(spark, join_path(args.input, "inputs", f"{name}.csv"), cols) for name, cols in INPUTS.items()}

    rent = T.rent_received_month(inputs["fact_rent_roll_month"], inputs["fact_rent_payment"])
    results = {
        "rent_received_month": rent,
        "water_bill_month": T.water_bill_month(inputs["fact_water_bill"]),
        "rent_received_trend": T.rent_received_trend(rent),
    }

    failed = False
    for name, df in results.items():
        rep = REPORTS[name]
        out_path = join_path(args.output, name)
        df.write.mode("overwrite").partitionBy(rep["partition_by"]).parquet(out_path)
        # read the Parquet back, so the files on disk are what gets checked
        written = spark.read.schema(ddl(rep["columns"])).parquet(out_path).select(*[c for c, _ in rep["columns"]])
        reference = read_csv(spark, join_path(args.input, "reference", f"{name}.csv"), rep["columns"])
        problems = T.reconcile(written, reference, rep["keys"]).cache()
        n_spark, n_ref, n_bad = written.count(), reference.count(), problems.count()
        status = "OK" if n_bad == 0 else "MISMATCH"
        print(f"{name}: {n_spark} rows in Spark (Parquet, partitioned by {rep['partition_by']}), "
              f"{n_ref} rows in PostgreSQL, {n_bad} problems -> {status}")
        if n_bad:
            failed = True
            problems.orderBy("issue", "key").show(20, truncate=False)
        if n_ref == 0 and not args.allow_empty:
            print(f"{name}: the PostgreSQL reference is empty - nothing was really compared", file=sys.stderr)
            failed = True

    print("RECONCILIATION FAILED" if failed else "All Spark reports match PostgreSQL.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
