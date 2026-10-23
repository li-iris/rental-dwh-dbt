"""Export and load helpers for the Snowflake layer: only the parts that need neither PostgreSQL nor Snowflake."""
import pytest

from helpers import load_script

export = load_script("export_gold.py")
sf = load_script("snowflake_load.py")


def test_postgres_types_map_to_snowflake_types():
    assert export.snowflake_type("text") == "VARCHAR"
    assert export.snowflake_type("character varying") == "VARCHAR"
    assert export.snowflake_type("integer") == "NUMBER(38,0)"
    assert export.snowflake_type("bigint") == "NUMBER(38,0)"
    assert export.snowflake_type("numeric", "12", "2") == "NUMBER(12,2)"
    assert export.snowflake_type("numeric", None, None) == "NUMBER(38,6)"      # unconstrained numeric
    assert export.snowflake_type("numeric", "60", "2") == "NUMBER(38,2)"       # Snowflake allows at most 38 digits
    assert export.snowflake_type("double precision") == "FLOAT"
    assert export.snowflake_type("boolean") == "BOOLEAN"
    assert export.snowflake_type("date") == "DATE"
    assert export.snowflake_type("timestamp without time zone") == "TIMESTAMP_NTZ"
    assert export.snowflake_type("uuid") == "VARCHAR"                          # anything unknown is kept as text


def test_only_synthetic_data_may_be_exported():
    assert export.only_synthetic(["Sample_working_list.xlsx", "Sample_working_list_2025-06.xlsx"])
    assert not export.only_synthetic(["Sample_working_list.xlsx", "someone_elses_list.xlsx"])
    assert not export.only_synthetic([])               # no evidence it is synthetic = refuse
    assert not export.only_synthetic([None, ""])


def test_safe_name_blocks_sql_injection():
    assert export.safe_name("gold") == "gold"
    with pytest.raises(ValueError):
        export.safe_name("gold; drop table x")
    with pytest.raises(ValueError):
        export.safe_name("Gold")


def test_export_refuses_without_explicit_database(monkeypatch, capsys):
    monkeypatch.delenv("PGDATABASE", raising=False)
    assert export.main(["somewhere"]) == 1
    assert "PGDATABASE" in capsys.readouterr().err


def test_create_table_sql():
    sql = sf.create_table_sql("fact_water_bill", [{"name": "water_bill_id", "type": "VARCHAR"},
                                                  {"name": "amount", "type": "NUMBER(12,2)"}])
    assert sql.startswith("CREATE OR REPLACE TABLE RAW.FACT_WATER_BILL")
    assert "WATER_BILL_ID VARCHAR" in sql and "AMOUNT NUMBER(12,2)" in sql


def test_load_sql_uses_the_tables_own_stage_and_cleans_up():
    assert sf.put_sql("dim_property", "/tmp/x/dim_property.csv").startswith("PUT 'file:///")
    assert "@RAW.%DIM_PROPERTY" in sf.put_sql("dim_property", "/tmp/x/dim_property.csv")
    copy = sf.copy_sql("dim_property")
    assert "COPY INTO RAW.DIM_PROPERTY FROM @RAW.%DIM_PROPERTY" in copy
    assert "SKIP_HEADER = 1" in copy and "ON_ERROR = ABORT_STATEMENT" in copy and "PURGE = TRUE" in copy


def test_table_names_are_checked_before_they_go_into_sql():
    with pytest.raises(ValueError):
        sf.table_ident("x; drop table y")


def test_count_csv_records_counts_rows_not_lines(tmp_path):
    p = tmp_path / "t.csv"
    p.write_text('id,note\n1,"line one\nline two"\n2,plain\n', encoding="utf-8")
    assert sf.count_csv_records(p) == 2                # a quoted line break is still one row
    header_only = tmp_path / "h.csv"
    header_only.write_text("id,note\n", encoding="utf-8")
    assert sf.count_csv_records(header_only) == 0
