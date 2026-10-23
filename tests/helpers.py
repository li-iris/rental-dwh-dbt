"""Load the numbered pipeline scripts (e.g. 01_extract_to_csv.py) as modules, so tests can call their functions."""
import importlib.util
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent / "scripts"


def load_script(filename: str):
    spec = importlib.util.spec_from_file_location("script_" + filename[:2], SCRIPTS / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
