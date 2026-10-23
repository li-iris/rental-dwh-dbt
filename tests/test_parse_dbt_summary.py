"""The Airflow DAG decides pass/fail from the dbt test summary line, so parsing it must be exact."""
from helpers import load_script

parse = load_script("parse_dbt_summary.py")

LOG = """12:00:01  Finished running 231 data tests in 0 hours 0 minutes
12:00:01  Done. PASS=218 WARN=13 ERROR=0 SKIP=0 NO-OP=0 TOTAL=231
"""


def test_parse_reads_counts():
    assert parse.parse(LOG) == (218, 13, 0)


def test_parse_uses_last_summary_line():
    assert parse.parse("Done. PASS=1 WARN=1 ERROR=1\n" + LOG) == (218, 13, 0)


def test_parse_returns_none_without_summary():
    assert parse.parse("Compilation Error in test x") is None


def test_main_exit_codes(tmp_path, capsys):
    good, bad, empty = tmp_path / "g.txt", tmp_path / "b.txt", tmp_path / "e.txt"
    good.write_text(LOG)
    bad.write_text("Done. PASS=200 WARN=3 ERROR=2 SKIP=0\n")
    empty.write_text("nothing\n")
    assert parse.main([str(good), "--fail-on-error"]) == 0
    assert capsys.readouterr().out.strip() == "218 13 0"
    assert parse.main([str(bad)]) == 0                       # without the flag, errors are only reported
    assert parse.main([str(bad), "--fail-on-error"]) == 2    # with it, a data ERROR stops the run
    assert parse.main([str(empty)]) == 1                     # dbt did not finish
