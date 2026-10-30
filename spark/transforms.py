"""Spark versions of three reports from the PostgreSQL warehouse, plus the row-for-row comparison used to check them.

Every function takes DataFrames and returns a DataFrame: no paths, no session settings, no I/O.
The runner (run_spark.py) does the reading and writing, so these work the same in local mode and on Databricks.
"""
from functools import reduce

from pyspark.sql import DataFrame, Window
from pyspark.sql import functions as F

from report_schemas import REPORTS


def _conform(df: DataFrame, report: str) -> DataFrame:
    """Column order and types exactly as declared in report_schemas.REPORTS (amounts become DECIMAL(14,2))."""
    return df.select(*[F.col(name).cast(spark_type).alias(name) for name, spark_type in REPORTS[report]["columns"]])


def _zero(col):
    return F.coalesce(col, F.lit(0))


# ---- 1. rent received per property and month (DataFrame API) ------------------------------------------------------
def rent_received_month(rent_roll: DataFrame, payments: DataFrame) -> DataFrame:
    """Same logic as dbt/models/gold/rpt_rent_received_month.sql: the rent roll month next to payments typed into
    entry.rent_payment, summed per property and month, and the total recorded minus the expected rent."""
    typed = (payments.where(F.col("property_id").isNotNull())
             .groupBy("property_id", "paid_month")
             .agg(F.sum("amount").alias("typed_received_aud")))
    r, t = rent_roll.alias("r"), typed.alias("t")
    joined = r.join(t, (F.col("r.property_id") == F.col("t.property_id"))
                    & (F.col("r.month_start") == F.col("t.paid_month")), "left")
    total = _zero(F.col("r.cash_received_aud")) + _zero(F.col("r.rmb_received_aud")) + _zero(F.col("t.typed_received_aud"))
    expected = F.coalesce(F.col("r.expected_rent_with_rules_aud"), F.col("r.expected_rent_aud"), F.lit(0))
    out = joined.select(
        F.col("r.property_id").alias("property_id"),
        F.col("r.month_start").alias("month_start"),
        F.col("r.rent_basis").alias("rent_basis"),
        F.col("r.expected_rent_aud").alias("expected_rent_aud"),
        F.col("r.expected_rent_with_rules_aud").alias("expected_rent_with_rules_aud"),
        F.col("r.cash_received_aud").alias("cash_received_aud"),
        F.col("r.rmb_received_aud").alias("rmb_received_aud"),
        F.col("t.typed_received_aud").alias("typed_received_aud"),
        total.alias("total_recorded_aud"),
        (total - expected).alias("recorded_minus_expected_with_rules_aud"),
    )
    return _conform(out, "rent_received_month")


# ---- 2. water bills per property and billing month (Spark SQL) ----------------------------------------------------
WATER_BILL_MONTH_SQL = """
SELECT
    property_id,
    trunc(period_start, 'MM')                                                                  AS bill_month,
    COUNT(*)                                                                                   AS bills,
    SUM(amount)                                                                                AS total_amount,
    SUM(CASE WHEN follow_up_status <> 'closed' THEN 1 ELSE 0 END)                              AS open_bills,
    COALESCE(SUM(CASE WHEN follow_up_status <> 'closed' THEN amount END), 0)                   AS open_amount,
    SUM(CASE WHEN follow_up_status IN ('invoice_overdue', 'payment_overdue') THEN 1 ELSE 0 END) AS overdue_bills,
    SUM(CASE WHEN may_be_unrecoverable THEN 1 ELSE 0 END)                                      AS may_be_unrecoverable_bills
FROM {bills}
GROUP BY property_id, trunc(period_start, 'MM')
"""


def water_bill_month(bills: DataFrame) -> DataFrame:
    """Water bills per property and month of period_start: how many, how much, how many still open or overdue.
    Bills without a property or a period start are kept, under an empty property / month."""
    out = bills.sparkSession.sql(WATER_BILL_MONTH_SQL, bills=bills)
    return _conform(out, "water_bill_month")


# ---- 3. month-over-month change and running total (window functions) ---------------------------------------------
def rent_received_trend(rent_received: DataFrame) -> DataFrame:
    """Per property: the previous calendar month's recorded total (empty when that month has no row - a gap is not
    treated as the previous month), the change against it, and the running total of recorded money."""
    w = Window.partitionBy("property_id").orderBy("month_start")
    prev_month_start = F.lag("month_start").over(w)
    prev_total = F.when(prev_month_start == F.add_months(F.col("month_start"), -1),
                        F.lag("total_recorded_aud").over(w))
    out = rent_received.select(
        "property_id",
        "month_start",
        "total_recorded_aud",
        prev_total.alias("prev_month_recorded_aud"),
        (F.col("total_recorded_aud") - prev_total).alias("mom_change_aud"),
        F.sum("total_recorded_aud").over(w.rowsBetween(Window.unboundedPreceding, Window.currentRow))
         .alias("running_recorded_aud"),
    )
    return _conform(out, "rent_received_trend")


# ---- reconciliation -----------------------------------------------------------------------------------------------
def _is_amount(spark_type: str) -> bool:
    return spark_type.startswith("decimal") or spark_type in ("double", "float")


def reconcile(actual: DataFrame, expected: DataFrame, keys) -> DataFrame:
    """Compare two results row for row. Returns one row per problem (empty = they agree):
         key        the key values joined with '|'
         issue      only_in_spark / only_in_reference / values_differ / duplicate_key_spark / duplicate_key_reference
         columns    for values_differ: the columns that differ
    Keys must match exactly (an empty key matches an empty key). Amounts must agree to the cent (both rounded to
    0.01); every other column must be equal, and empty only where the other side is empty too."""
    keys = list(keys)
    values = [c for c in actual.columns if c not in keys]
    types = dict(actual.dtypes)

    def key_text(cols):
        return F.concat_ws("|", *[F.coalesce(c.cast("string"), F.lit("<empty>")) for c in cols])

    def duplicates(df, label):
        return (df.groupBy(*keys).count().where(F.col("count") > 1)
                .select(key_text([F.col(k) for k in keys]).alias("key"), F.lit(label).alias("issue"),
                        F.lit("").alias("columns")))

    a = actual.select(*[F.col(c).alias("a_" + c) for c in actual.columns], F.lit(True).alias("_in_spark"))
    e = expected.select(*[F.col(c).alias("e_" + c) for c in expected.columns], F.lit(True).alias("_in_ref"))
    on = reduce(lambda x, y: x & y, [F.col("a_" + k).eqNullSafe(F.col("e_" + k)) for k in keys])
    j = a.join(e, on, "full_outer")

    def differs(c):
        x, y = F.col("a_" + c), F.col("e_" + c)
        if _is_amount(types[c]):
            same = (x.isNull() & y.isNull()) | (x.isNotNull() & y.isNotNull() & (F.round(x, 2) == F.round(y, 2)))
        else:
            same = x.eqNullSafe(y)
        return ~same

    diff_cols = F.concat_ws(",", *[F.when(differs(c), F.lit(c)) for c in values]) if values else F.lit("")
    issue = (F.when(F.col("_in_ref").isNull(), F.lit("only_in_spark"))
              .when(F.col("_in_spark").isNull(), F.lit("only_in_reference"))
              .when(diff_cols != "", F.lit("values_differ")))
    key = key_text([F.coalesce(F.col("a_" + k), F.col("e_" + k)) for k in keys])
    rows = (j.select(key.alias("key"), issue.alias("issue"),
                     F.when(issue == "values_differ", diff_cols).otherwise(F.lit("")).alias("columns"))
             .where(F.col("issue").isNotNull()))
    return rows.unionByName(duplicates(actual, "duplicate_key_spark")).unionByName(duplicates(expected, "duplicate_key_reference"))
