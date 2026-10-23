"""Step 2b: the layout guard must notice when someone inserts or renames a column in Excel."""
import csv
import json
import sys

from helpers import load_script

layout = load_script("02b_check_layout.py")
META = ["_source_file", "_file_sha256", "_sheet", "_row_number"]


def _sheet_csv(folder, name, headers, sheet="0.Tenant"):
    p = folder / name
    letters = [chr(65 + i) for i in range(len(headers))]
    with open(p, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        w.writerow(META + letters)
        w.writerow(["f.xlsx", "h", sheet, "1"] + headers)
        w.writerow(["f.xlsx", "h", sheet, "2"] + ["data"] * len(headers))
    return p


def test_fingerprint_reads_header_row(tmp_path):
    p = _sheet_csv(tmp_path, "a.csv", ["Name", "Rent"])
    sheet, fp = layout.fingerprint(p)
    assert sheet == "0.Tenant"
    assert fp["width"] == 2
    assert fp["headers"] == {"A": "Name", "B": "Rent"}


def _run(monkeypatch, folder, baseline, *extra):
    monkeypatch.setattr(layout, "BASELINE", baseline)
    monkeypatch.setattr(sys, "argv", ["02b", str(folder), *extra])
    return layout.main()


def test_first_run_creates_baseline(tmp_path, monkeypatch):
    _sheet_csv(tmp_path, "a.csv", ["Name", "Rent"])
    baseline = tmp_path / "cfg" / "layout.json"
    assert _run(monkeypatch, tmp_path, baseline) == 0
    assert "0.Tenant" in json.loads(baseline.read_text())


def test_same_layout_passes(tmp_path, monkeypatch):
    _sheet_csv(tmp_path, "a.csv", ["Name", "Rent"])
    baseline = tmp_path / "layout.json"
    _run(monkeypatch, tmp_path, baseline)
    assert _run(monkeypatch, tmp_path, baseline) == 0


def test_inserted_column_is_detected(tmp_path, monkeypatch):
    _sheet_csv(tmp_path, "a.csv", ["Name", "Rent"])
    baseline = tmp_path / "layout.json"
    _run(monkeypatch, tmp_path, baseline)
    _sheet_csv(tmp_path, "a.csv", ["Name", "Phone", "Rent"])   # someone inserted a column
    assert _run(monkeypatch, tmp_path, baseline) == 3


def test_accept_updates_baseline(tmp_path, monkeypatch):
    _sheet_csv(tmp_path, "a.csv", ["Name", "Rent"])
    baseline = tmp_path / "layout.json"
    _run(monkeypatch, tmp_path, baseline)
    _sheet_csv(tmp_path, "a.csv", ["Name", "Phone", "Rent"])
    assert _run(monkeypatch, tmp_path, baseline, "--accept") == 0
    assert _run(monkeypatch, tmp_path, baseline) == 0
