#!/usr/bin/env python3
"""Report production-source coverage and enforce explicit, measured line floors."""

import argparse
import json
import math
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parent.parent
MODULES = {"ShimaCore", "Shima", "ShimaUpdater", "shimactl"}


def percentage(value):
    number = float(value)
    if not math.isfinite(number) or not 0 <= number <= 100:
        raise argparse.ArgumentTypeError("coverage floors must be between 0 and 100")
    return number


def export_report():
    """Include every executable, even modules not linked into a test bundle."""
    bin_path = Path(subprocess.check_output(
        ["swift", "build", "--show-bin-path"], cwd=ROOT, text=True).strip())
    codecov_path = Path(subprocess.check_output(
        ["swift", "test", "--show-codecov-path"], cwd=ROOT, text=True).strip())
    profile = codecov_path.parent / "default.profdata"
    tests = sorted(path for path in bin_path.glob("*.xctest/Contents/MacOS/*") if path.is_file())
    executables = [bin_path / name for name in ["Shima", "ShimaUpdater", "shimactl"]]
    if not tests or not profile.is_file() or not all(path.is_file() for path in executables):
        raise ValueError("run swift test --enable-code-coverage before reporting coverage")
    objects = tests + executables
    command = ["xcrun", "llvm-cov", "export", str(objects[0]), "-instr-profile=" + str(profile)]
    for path in objects[1:]:
        command += ["-object", str(path)]
    destination = ROOT / ".build" / "audit-coverage.json"
    with destination.open("w") as output:
        subprocess.run(command, cwd=ROOT, stdout=output, check=True)
    return destination


def counts(report):
    sources = ROOT / "Sources"
    modules = set()
    module_lines = {module: 0 for module in MODULES}
    seen = set()
    core = [0, 0]
    overall = [0, 0]
    data = report["data"]
    if not isinstance(data, list) or not data:
        raise ValueError("no coverage data")
    for entry in data:
        for file in entry["files"]:
            path = Path(file["filename"]).resolve(strict=False)
            try:
                relative = path.relative_to(sources)
            except ValueError:
                continue
            if len(relative.parts) < 2 or relative.parts[0] not in MODULES:
                continue
            if path in seen:
                raise ValueError("duplicate production source: " + str(path))
            seen.add(path)
            module = relative.parts[0]
            modules.add(module)
            lines = file["summary"]["lines"]
            covered, count = lines["covered"], lines["count"]
            if type(covered) is not int or type(count) is not int or not 0 <= covered <= count:
                raise ValueError("invalid line counts for " + str(path))
            overall[0] += covered
            overall[1] += count
            module_lines[module] += count
            if module == "ShimaCore":
                core[0] += covered
                core[1] += count
    missing = MODULES - modules
    if missing:
        raise ValueError("Missing production coverage: " + ", ".join(sorted(missing)))
    empty = {module for module in MODULES if not module_lines[module]}
    if empty:
        raise ValueError("Empty production coverage: " + ", ".join(sorted(empty)))
    if not core[1] or not overall[1]:
        raise ValueError("empty production line counts")
    return [("ShimaCore", core), ("Overall production", overall)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, help="validate an existing llvm-cov JSON export")
    parser.add_argument("--core-floor", required=True, type=percentage)
    parser.add_argument("--overall-floor", required=True, type=percentage)
    args = parser.parse_args()
    try:
        report_path = args.report or export_report()
        with report_path.open() as source:
            result = counts(json.load(source))
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        print("Invalid coverage report: " + str(error), file=sys.stderr)
        return 2
    failed = False
    for (label, (covered, count)), floor in zip(result, [args.core_floor, args.overall_floor]):
        percent = 100 * covered / count
        print(f"{label}: {percent:.2f}% ({covered}/{count}); floor {floor:.2f}%")
        if percent < floor:
            print(f"{label} is below its {floor:.2f}% coverage floor.", file=sys.stderr)
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
