"""OPTIONAL and NOT TESTED in this repository's CI: an Airflow DAG that runs the same refresh as scripts/run_all.sh.

The project works without Airflow (cron/launchd/GitHub Actions). This file only shows how the steps would be
split into tasks if a scheduler with retries and a UI were wanted. Needs Airflow 2.x and the repo at $RENTAL_DWH_HOME.
"""
import os
from datetime import datetime

from airflow import DAG
from airflow.operators.bash import BashOperator

HOME = os.environ.get("RENTAL_DWH_HOME", "/opt/rental-dwh")

with DAG("rental_dwh_daily", start_date=datetime(2026, 1, 1), schedule="0 6 * * *", catchup=False,
         default_args={"retries": 1}) as dag:
    load = BashOperator(task_id="excel_to_bronze", bash_command=(
        f"cd {HOME} && python scripts/01_extract_to_csv.py raw_private && "
        "python scripts/02b_check_layout.py raw_private/bronze_csv && "
        "python scripts/02_load_bronze.py raw_private/bronze_csv"))
    seed = BashOperator(task_id="dbt_seed", bash_command=f"cd {HOME}/dbt && dbt seed --full-refresh")
    run = BashOperator(task_id="dbt_run", bash_command=f"cd {HOME}/dbt && dbt run")
    test = BashOperator(task_id="dbt_test", bash_command=f"cd {HOME}/dbt && dbt test --store-failures || true")
    report = BashOperator(task_id="reports", bash_command=f"cd {HOME} && python scripts/05_export_problem_list.py && python scripts/06_record_history.py 0 0 0 airflow")
    load >> seed >> run >> test >> report
