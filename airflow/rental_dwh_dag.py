"""Airflow DAG with the same steps as scripts/run_all.sh, one task per step.

What is verified: the `airflow` job in .github/workflows/ci.yml installs Airflow 2.10, checks that this file imports
and that the task order is right, then runs the whole DAG once with `airflow dags test` against the synthetic data.
What is NOT done: this is not deployed to a long-running scheduler; the project itself still refreshes with run_all.sh.

A failed data check (dbt ERROR) fails the dbt_test task and stops the run; follow-up warnings never do.
"""
import os
from datetime import datetime
from pathlib import Path

from airflow import DAG
from airflow.operators.bash import BashOperator

HOME = os.environ.get("RENTAL_DWH_HOME", str(Path(__file__).resolve().parents[1]))
DB = os.environ.get("PGDATABASE", "rental_dwh")

with DAG(
    "rental_dwh_daily",
    start_date=datetime(2026, 1, 1),
    schedule="0 6 * * *",
    catchup=False,
    max_active_runs=1,
    default_args={"retries": 1},
    tags=["rental-dwh"],
    doc_md=__doc__,
) as dag:
    db_objects = BashOperator(task_id="db_objects", bash_command=(
        f"cd {HOME} && mkdir -p logs reports backups && psql -X -q -v ON_ERROR_STOP=1 -d {DB} -f sql/10_entry_schema.sql > /dev/null && "
        f"psql -X -q -v ON_ERROR_STOP=1 -d {DB} -f sql/30_history.sql > /dev/null"))

    extract = BashOperator(task_id="extract_excel", bash_command=(
        f"cd {HOME} && python scripts/01_extract_to_csv.py raw_private"))

    check_layout = BashOperator(task_id="check_layout", bash_command=(
        f"cd {HOME} && python scripts/02b_check_layout.py raw_private/bronze_csv"))

    load_bronze = BashOperator(task_id="load_bronze", bash_command=(
        f"cd {HOME} && python scripts/02_load_bronze.py raw_private/bronze_csv {DB}"))

    dbt_seed = BashOperator(task_id="dbt_seed", bash_command=f"cd {HOME}/dbt && dbt seed --full-refresh")

    dbt_run = BashOperator(task_id="dbt_run", bash_command=f"cd {HOME}/dbt && dbt run")

    dbt_test = BashOperator(task_id="dbt_test", retries=0, bash_command=(
        f"mkdir -p {HOME}/logs && cd {HOME}/dbt && "
        "(dbt test --store-failures > ../logs/last_dbt_test.txt 2>&1; true) && "
        "tail -25 ../logs/last_dbt_test.txt && "
        f"cd {HOME} && python scripts/parse_dbt_summary.py logs/last_dbt_test.txt --fail-on-error"))

    reports = BashOperator(task_id="reports", bash_command=(
        f"cd {HOME} && python scripts/05_export_problem_list.py && python scripts/04_export_management_report.py"))

    history = BashOperator(task_id="record_history", bash_command=(
        f"cd {HOME} && python scripts/06_record_history.py $(python scripts/parse_dbt_summary.py logs/last_dbt_test.txt) airflow"))

    db_objects >> extract >> check_layout >> load_bronze >> dbt_seed >> dbt_run >> dbt_test >> reports >> history
