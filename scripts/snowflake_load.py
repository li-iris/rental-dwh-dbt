"""Load the CSV files written by export_gold.py into Snowflake (schema RAW), then check the row counts.

    source ~/.snowflake/env.sh
    python scripts/snowflake_load.py raw_private/gold_csv

Needs the snowflake-connector-python package (comes with dbt-snowflake) and these environment variables:
    SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER, SNOWFLAKE_PRIVATE_KEY_PATH   (key-pair login, no password anywhere)
    SNOWFLAKE_ROLE (DBT_ROLE), SNOWFLAKE_WAREHOUSE (RENTAL_WH), SNOWFLAKE_DATABASE (RENTAL_DWH)

Each file goes through the table's own internal stage (PUT) and then COPY INTO. Re-running replaces the tables.
Loading from S3 instead of PUT only changes where the files are read from; see the README.
"""
import csv
import json
import os
import re
import sys
from pathlib import Path

csv.field_size_limit(10 * 1024 * 1024)


def table_ident(name: str) -> str:
    if not re.fullmatch(r"[a-z_][a-z_0-9]*", name):
        raise ValueError(f"unsafe table name: {name!r}")
    return name.upper()


def create_table_sql(table: str, columns) -> str:
    cols = ",\n  ".join(f'{table_ident(c["name"])} {c["type"]}' for c in columns)
    return f"CREATE OR REPLACE TABLE RAW.{table_ident(table)} (\n  {cols}\n)"


def put_sql(table: str, path) -> str:
    return f"PUT 'file://{Path(path).resolve()}' @RAW.%{table_ident(table)} AUTO_COMPRESS = TRUE OVERWRITE = TRUE"


def copy_sql(table: str) -> str:
    t = table_ident(table)
    return (f"COPY INTO RAW.{t} FROM @RAW.%{t} "
            "FILE_FORMAT = (TYPE = CSV SKIP_HEADER = 1 FIELD_OPTIONALLY_ENCLOSED_BY = '\"' EMPTY_FIELD_AS_NULL = TRUE) "
            "ON_ERROR = ABORT_STATEMENT PURGE = TRUE")


def count_csv_records(path) -> int:
    """Data rows in a CSV file (header excluded); quoted line breaks inside a cell count as one row."""
    with open(path, newline="", encoding="utf-8") as f:
        return max(sum(1 for _ in csv.reader(f)) - 1, 0)


def connect():
    import snowflake.connector
    from cryptography.hazmat.primitives import serialization

    key = serialization.load_pem_private_key(Path(os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"]).read_bytes(), password=None)
    der = key.private_bytes(encoding=serialization.Encoding.DER, format=serialization.PrivateFormat.PKCS8,
                            encryption_algorithm=serialization.NoEncryption())
    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"], user=os.environ["SNOWFLAKE_USER"], private_key=der,
        role=os.environ.get("SNOWFLAKE_ROLE", "DBT_ROLE"),
        warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE", "RENTAL_WH"),
        database=os.environ.get("SNOWFLAKE_DATABASE", "RENTAL_DWH"))


def load_folder(folder, conn) -> dict:
    folder = Path(folder)
    schema = json.loads((folder / "_schema.json").read_text())
    cur = conn.cursor()
    cur.execute("CREATE SCHEMA IF NOT EXISTS RAW")
    counts = {}
    for table, columns in schema.items():
        path = folder / f"{table}.csv"
        cur.execute(create_table_sql(table, columns))
        cur.execute(put_sql(table, path))
        cur.execute(copy_sql(table))
        cur.execute(f"SELECT COUNT(*) FROM RAW.{table_ident(table)}")
        loaded, expected = cur.fetchone()[0], count_csv_records(path)
        if loaded != expected:
            raise RuntimeError(f"{table}: {loaded} rows in Snowflake but {expected} in the CSV file")
        counts[table] = loaded
        print(f"{table}: {loaded} rows loaded")
    return counts


def main(argv) -> int:
    if len(argv) != 1:
        print(__doc__)
        return 1
    conn = connect()
    try:
        load_folder(argv[0], conn)
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
