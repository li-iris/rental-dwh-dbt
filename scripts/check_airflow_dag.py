"""Run with the Python of the Airflow environment (CI does this): the DAG must import and keep the right task order."""
from pathlib import Path

from airflow.models import DagBag

EXPECTED = ["db_objects", "extract_excel", "check_layout", "load_bronze", "dbt_seed", "dbt_run",
            "dbt_test", "reports", "record_history"]

bag = DagBag(dag_folder=str(Path(__file__).resolve().parents[1] / "airflow"), include_examples=False)
assert not bag.import_errors, f"DAG import errors: {bag.import_errors}"
dag = bag.dags.get("rental_dwh_daily")
assert dag is not None, "DAG rental_dwh_daily not found"
order = [t.task_id for t in dag.topological_sort()]
assert order == EXPECTED, f"task order changed: {order}"
print("DAG ok:", " -> ".join(order))
