"""Unit tests for spark/transforms.py on small in-memory DataFrames (local Spark, one core).

Skipped when pyspark is not installed, so `make test` works without Java and Spark.
Set REQUIRE_PYSPARK=1 (as the CI spark job does) to fail instead of skipping.
"""
import os
import sys
from datetime import date
from decimal import Decimal as D
from pathlib import Path

import pytest

if os.environ.get("REQUIRE_PYSPARK"):
    import pyspark  # noqa: F401
else:
    pytest.importorskip("pyspark")

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "spark"))

from pyspark.sql import SparkSession  # noqa: E402

import transforms as T  # noqa: E402
from report_schemas import INPUTS, REPORTS, ddl  # noqa: E402

JUL, AUG, SEP, OCT = date(2025, 7, 1), date(2025, 8, 1), date(2025, 9, 1), date(2025, 10, 1)


@pytest.fixture(scope="module")
def spark():
    if os.environ.get("DATABRICKS_RUNTIME_VERSION"):
        # On Databricks: use the session the workspace already provides (serverless or a cluster); never stop it.
        s = SparkSession.builder.getOrCreate()
        s.conf.set("spark.sql.session.timeZone", "UTC")
        yield s
        return
    s = (SparkSession.builder.master("local[1]").appName("rental_dwh_spark_tests")
         .config("spark.sql.shuffle.partitions", "1").config("spark.ui.enabled", "false")
         .config("spark.sql.session.timeZone", "UTC").getOrCreate())
    yield s
    s.stop()


def rows(df):
    return {tuple(r) for r in df.collect()}


def declared(report):
    return [(name, t.lower().replace(" ", "")) for name, t in REPORTS[report]["columns"]]


# ---- rent received per property and month ----------------------------------------------------------------------
def test_rent_received_month_adds_typed_payments_and_compares_with_expected(spark):
    roll = spark.createDataFrame([
        ("p1", JUL, "unit_rent", D("2000"), D("2000"), D("1500"), None),
        ("p1", AUG, "unclear", None, D("1800.50"), None, D("300")),
        ("p2", JUL, "no_tenancy", None, None, None, None),
    ], ddl(INPUTS["fact_rent_roll_month"]))
    payments = spark.createDataFrame([
        ("p1", JUL, D("400")),
        ("p1", JUL, D("-50.25")),        # a refund
        (None, JUL, D("999")),           # payment whose address matched no property: not counted
        ("p2", SEP, D("100")),           # month not in the rent roll: not in the report (same as the dbt left join)
    ], ddl(INPUTS["fact_rent_payment"]))

    out = T.rent_received_month(roll, payments)

    assert out.dtypes == declared("rent_received_month")
    assert rows(out) == {
        ("p1", JUL, "unit_rent", D("2000.00"), D("2000.00"), D("1500.00"), None, D("349.75"), D("1849.75"), D("-150.25")),
        # no expected rent (unclear): the rule-based expectation is used
        ("p1", AUG, "unclear", None, D("1800.50"), None, D("300.00"), None, D("300.00"), D("-1500.50")),
        ("p2", JUL, "no_tenancy", None, None, None, None, None, D("0.00"), D("0.00")),
    }


# ---- water bills per property and month (Spark SQL) ------------------------------------------------------------
def test_water_bill_month_counts_open_overdue_and_unrecoverable(spark):
    bills = spark.createDataFrame([
        ("w1", "p1", date(2025, 7, 3), D("120.10"), "closed", False),
        ("w2", "p1", date(2025, 7, 20), D("80"), "invoice_overdue", True),
        ("w3", "p1", date(2025, 8, 1), D("50"), "awaiting_payment", False),
        ("w5", "p1", date(2025, 8, 15), None, "company_not_paid_yet", False),   # amount unknown
        ("w4", None, None, D("10"), "payment_overdue", False),                  # no property, no period
    ], ddl(INPUTS["fact_water_bill"]))

    out = T.water_bill_month(bills)

    assert out.dtypes == declared("water_bill_month")
    assert rows(out) == {
        ("p1", JUL, 2, D("200.10"), 1, D("80.00"), 1, 1),
        ("p1", AUG, 2, D("50.00"), 2, D("50.00"), 0, 0),
        (None, None, 1, D("10.00"), 1, D("10.00"), 1, 0),
    }


# ---- month-over-month change and running total (window functions) ----------------------------------------------
def test_trend_uses_previous_calendar_month_and_running_total(spark):
    received = spark.createDataFrame([
        ("p1", JUL, D("100")),
        ("p1", AUG, D("150.50")),
        ("p1", OCT, D("120")),           # September has no row: October has no previous month to compare with
        ("p2", AUG, D("0")),
    ], "property_id STRING, month_start DATE, total_recorded_aud DECIMAL(14,2)")

    out = T.rent_received_trend(received)

    assert out.dtypes == declared("rent_received_trend")
    assert rows(out) == {
        ("p1", JUL, D("100.00"), None, None, D("100.00")),
        ("p1", AUG, D("150.50"), D("100.00"), D("50.50"), D("250.50")),
        ("p1", OCT, D("120.00"), None, None, D("370.50")),
        ("p2", AUG, D("0.00"), None, None, D("0.00")),
    }


# ---- reconciliation --------------------------------------------------------------------------------------------
SCHEMA_A = "k1 STRING, k2 DATE, n BIGINT, amt DECIMAL(14,2), txt STRING"
SCHEMA_E = "k1 STRING, k2 DATE, n BIGINT, amt DECIMAL(20,6), txt STRING"
ACTUAL = [("a", JUL, 1, D("10.00"), "x"), (None, None, 2, D("5.00"), "y"), ("b", JUL, 1, D("1.00"), "z")]


def test_reconcile_identical_results_have_no_problems(spark):
    a = spark.createDataFrame(ACTUAL, SCHEMA_A)
    e = spark.createDataFrame(ACTUAL, SCHEMA_E)
    assert T.reconcile(a, e, ["k1", "k2"]).count() == 0


def test_reconcile_reports_missing_extra_and_tolerates_sub_cent_differences(spark):
    a = spark.createDataFrame(ACTUAL, SCHEMA_A)
    e = spark.createDataFrame([
        ("a", JUL, 1, D("10.004"), "x"),          # same to the cent
        (None, None, 2, D("5.00"), "y"),          # empty keys match empty keys
        ("c", JUL, 1, D("1.00"), "z"),            # only in the reference; b is only in Spark
    ], SCHEMA_E)
    assert rows(T.reconcile(a, e, ["k1", "k2"])) == {
        ("b|2025-07-01", "only_in_spark", ""),
        ("c|2025-07-01", "only_in_reference", ""),
    }


def test_reconcile_names_the_columns_that_differ(spark):
    a = spark.createDataFrame(ACTUAL, SCHEMA_A)
    e = spark.createDataFrame([
        ("a", JUL, 1, D("10.02"), None),          # two cents off, and a value that became empty
        (None, None, 3, D("5.00"), "y"),
        ("b", JUL, 1, D("1.00"), "z"),
    ], SCHEMA_E)
    assert rows(T.reconcile(a, e, ["k1", "k2"])) == {
        ("a|2025-07-01", "values_differ", "amt,txt"),
        ("<empty>|<empty>", "values_differ", "n"),
    }


def test_reconcile_reports_duplicate_keys(spark):
    a = spark.createDataFrame(ACTUAL + [ACTUAL[0]], SCHEMA_A)
    e = spark.createDataFrame(ACTUAL, SCHEMA_E)
    assert rows(T.reconcile(a, e, ["k1", "k2"])) == {("a|2025-07-01", "duplicate_key_spark", "")}
