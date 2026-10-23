"""Step 2 helpers (the parts that do not need a database)."""
import csv

import pytest

from helpers import load_script

load = load_script("02_load_bronze.py")


def test_letters_follow_excel_column_names():
    cols = load.letters(28)
    assert cols[0] == "A" and cols[25] == "Z"
    assert cols[26:] == ["AA", "AB"]


def test_col_name_prefix_keeps_metadata_columns():
    assert load.col_name("A") == "c_a"
    assert load.col_name("AB") == "c_ab"
    assert load.col_name("_source_file") == "_source_file"


def test_sql_str_escapes_quotes():
    assert load.sql_str("O'Brien") == "'O''Brien'"
    assert load.sql_str("a'; drop table x; --") == "'a''; drop table x; --'"


def test_sensitive_sheets_are_never_loaded():
    # data minimisation rule: these sheets must not map to any table
    for sheet in load.EXCLUDED_SHEETS:
        assert sheet not in load.SHEET_TO_TABLE


def test_table_names_are_unique():
    tables = list(load.SHEET_TO_TABLE.values())
    assert len(tables) == len(set(tables))


def _write_csv(path, rows):
    with open(path, "w", newline="", encoding="utf-8-sig") as f:
        csv.writer(f).writerows(rows)


def test_read_csv_info_counts_rows_and_width(tmp_path):
    header = load.META_COLS + ["A", "B"]
    p = tmp_path / "x.csv"
    _write_csv(p, [header, ["f.xlsx", "abc", "Sheet", "1", "x", "y"], ["f.xlsx", "abc", "Sheet", "2", "", "z"]])
    info = load.read_csv_info(p)
    assert info["rows"] == 2
    assert info["width"] == 2
    assert info["sha"] == "abc"
    assert info["sheet"] == "Sheet"


def test_read_csv_info_returns_none_for_header_only_file(tmp_path):
    p = tmp_path / "empty.csv"
    _write_csv(p, [load.META_COLS + ["A"]])
    assert load.read_csv_info(p) is None
