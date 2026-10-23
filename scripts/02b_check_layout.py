"""Check that the Excel layout has not changed before loading it.

The loader reads columns by position (c_a, c_b, ...). If someone inserts a column in a sheet, every later column
silently shifts and the numbers go wrong. This script compares the header rows of every sheet with
the layout saved last time in config/expected_layout.json and stops with a clear message when something moved.

First run: the layout is saved as the baseline.
After an intended change:  python scripts/02b_check_layout.py raw_private/bronze_csv --accept

Run:  python scripts/02b_check_layout.py raw_private/bronze_csv
Exit code: 0 = same layout (or baseline created), 3 = layout changed.
"""
import csv
import json
import sys
from pathlib import Path

csv.field_size_limit(10 * 1024 * 1024)
ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "config" / "expected_layout.json"
META = ["_source_file", "_file_sha256", "_sheet", "_row_number"]
# how many rows at the top of each sheet are headers (the silver models start reading data after these rows)
HEADER_ROWS = {"rent credit": 2, "1.招租+入住+退租list": 4, "5.1查房和消防通知": 2, "搬家工作记录": 2}


def fingerprint(path: Path):
    """{'sheet': title, 'width': n, 'headers': {'c_a': 'text', ...}} from the first two rows of one CSV."""
    with open(path, newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        headers, width, sheet = {}, 0, None
        for row in reader:
            sheet = row["_sheet"].strip()
            if int(row["_row_number"]) <= HEADER_ROWS.get(sheet, 1):
                for k, v in row.items():
                    if k not in META and v and v.strip():
                        headers.setdefault(k, []).append(v.strip())
            else:
                break
        width = len([h for h in (reader.fieldnames or []) if h not in META])
    return sheet, {"width": width, "headers": {k: " | ".join(v) for k, v in headers.items()}}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    accept = "--accept" in sys.argv
    folder = Path(args[0] if args else "raw_private/bronze_csv")
    current = {}
    for p in sorted(folder.glob("*.csv")):
        if p.name == "_inventory.csv":
            continue
        sheet, fp = fingerprint(p)
        if sheet:
            current.setdefault(sheet, fp)  # first file wins; versions of a sheet are compared to the baseline, not to each other
            # keep the widest layout if several workbook versions have the same sheet
            if fp["width"] > current[sheet]["width"]:
                current[sheet] = fp
    if not BASELINE.exists() or accept:
        BASELINE.parent.mkdir(exist_ok=True)
        BASELINE.write_text(json.dumps(current, ensure_ascii=False, indent=1, sort_keys=True))
        print(f"Layout baseline {'updated' if accept else 'created'}: {BASELINE} ({len(current)} sheets)")
        return 0
    base = json.loads(BASELINE.read_text())
    problems = []
    for sheet, fp in current.items():
        if sheet not in base:
            problems.append(f"NEW sheet not in the baseline: {sheet}")
            continue
        b = base[sheet]
        if fp["width"] != b["width"]:
            problems.append(f"{sheet}: {fp['width']} columns now, {b['width']} before - columns were added or removed")
        for col, text in fp["headers"].items():
            if col in b["headers"] and b["headers"][col] != text:
                problems.append(f"{sheet}: column {col} header changed from '{b['headers'][col]}' to '{text}'")
            elif col not in b["headers"]:
                problems.append(f"{sheet}: column {col} now has a header '{text}' (it was empty)")
        for col in b["headers"]:
            if col not in fp["headers"]:
                problems.append(f"{sheet}: column {col} lost its header '{b['headers'][col]}'")
    for sheet in base:
        if sheet not in current:
            problems.append(f"Sheet missing from the new files: {sheet}")
    if problems:
        print("The Excel layout changed. Columns are read by position, so numbers would be wrong. Check:")
        for m in problems:
            print("  -", m)
        print("If this change is intended, run with --accept after updating the models that read those columns.")
        return 3
    print(f"Layout check passed: {len(current)} sheets have the same columns and headers as the baseline.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
