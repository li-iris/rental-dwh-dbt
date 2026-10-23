"""Read the last 'Done. PASS=.. WARN=.. ERROR=..' line of a `dbt test` log and print "PASS WARN ERROR".

Usage:  python scripts/parse_dbt_summary.py logs/last_dbt_test.txt [--fail-on-error]
Exit code: 0 = ok, 1 = no summary line found (dbt did not finish), 2 = --fail-on-error and ERROR > 0.
Used by the Airflow DAG so a failed data check stops the run (warnings = follow-ups never do).
"""
import re
import sys

PATTERN = re.compile(r"Done\. PASS=(\d+) WARN=(\d+) ERROR=(\d+)")


def parse(text: str):
    """Return (passed, warned, errored) from the last summary line, or None if there is none."""
    found = PATTERN.findall(text)
    if not found:
        return None
    return tuple(int(x) for x in found[-1])


def main(argv) -> int:
    paths = [a for a in argv if not a.startswith("--")]
    if not paths:
        print(__doc__)
        return 1
    with open(paths[0], encoding="utf-8", errors="replace") as f:
        result = parse(f.read())
    if result is None:
        print("no dbt summary line found in", paths[0], file=sys.stderr)
        return 1
    print(*result)
    if "--fail-on-error" in argv and result[2] > 0:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
