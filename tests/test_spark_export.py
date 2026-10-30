"""Spark layer, the parts that need neither Spark nor PostgreSQL: declared schemas, export queries, safety checks."""
import importlib.util
from pathlib import Path

import pytest

SPARK_DIR = Path(__file__).resolve().parent.parent / "spark"


def _load(name):
    spec = importlib.util.spec_from_file_location("spark_" + name, SPARK_DIR / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


rs = _load("report_schemas")
export = _load("export_inputs")


def test_spark_types_map_to_postgres_casts():
    assert rs.pg_cast("STRING") == "text"
    assert rs.pg_cast("DATE") == "date"
    assert rs.pg_cast("BIGINT") == "bigint"
    assert rs.pg_cast("DECIMAL(14,2)") == "numeric(14,2)"
    assert rs.pg_cast("decimal(18, 6)") == "numeric(18,6)"
    assert rs.pg_cast("BOOLEAN") == "text"          # PostgreSQL CSV writes t/f; as text it is true/false, which Spark reads
    with pytest.raises(ValueError):
        rs.pg_cast("MAP<STRING,INT>")


def test_export_query_casts_every_declared_column():
    q = rs.export_query([("property_id", "STRING"), ("amount", "DECIMAL(14,2)")], "gold.fact_water_bill")
    assert "(property_id)::text as property_id" in q
    assert "(amount)::numeric(14,2) as amount" in q
    assert q.rstrip().endswith("from gold.fact_water_bill src")
    assert rs.ddl([("property_id", "STRING"), ("amount", "DECIMAL(14,2)")]) == "property_id STRING, amount DECIMAL(14,2)"


def test_every_report_declares_its_keys_and_partition_column():
    for name, rep in rs.REPORTS.items():
        cols = [c for c, _ in rep["columns"]]
        assert set(rep["keys"]) <= set(cols), name
        assert rep["partition_by"] in cols, name
        kind, ref = rep["reference"]
        assert kind in ("table", "sql")
        if kind == "sql":
            assert (SPARK_DIR / "reference_sql" / ref).is_file()


def test_export_jobs_cover_inputs_and_references():
    jobs = {(sub, stem): q for sub, stem, q in export.jobs("gold")}
    assert set(jobs) == {("inputs", t) for t in rs.INPUTS} | {("reference", r) for r in rs.REPORTS}
    assert "from gold.rpt_rent_received_month src" in jobs[("reference", "rent_received_month")]
    water = jobs[("reference", "water_bill_month")]
    assert "from gold.fact_water_bill" in water and "{gold}" not in water
    assert water.rstrip().endswith(") src")       # the reference query is wrapped as a sub-query and cast column by column


def test_spark_export_refuses_without_explicit_database(monkeypatch, capsys, tmp_path):
    monkeypatch.delenv("PGDATABASE", raising=False)
    assert export.main([str(tmp_path / "out")]) == 1
    assert "PGDATABASE" in capsys.readouterr().err
    assert not (tmp_path / "out").exists()


def test_spark_export_refuses_non_synthetic_data(monkeypatch, tmp_path):
    monkeypatch.setenv("PGDATABASE", "somewhere")
    calls = []

    def fake_psql(db, *args):
        calls.append(args)
        return "Sample_working_list.xlsx\nreal_agency_list.xlsx\n"

    monkeypatch.setattr(export.eg, "psql", fake_psql)
    assert export.main([str(tmp_path / "out")]) == 2
    assert len(calls) == 1                                  # only the bronze check ran; nothing was exported
    assert not (tmp_path / "out").exists()
