#!/usr/bin/env python3
"""Render an `info-process report` JSON file as a Markdown coverage table.

The numbers are the ones Coverview shows in its summary table.
"""
import json
import sys


def main(path: str) -> None:
    report = json.load(open(path))["report"]
    print("| Dataset | Coverage | Hit | Total | % |")
    print("|---|---|---:|---:|---:|")
    for dataset, types in report.items():
        for cov_type, data in types.items():
            hit = data["summary"]["hit"]
            total = data["summary"]["total"]
            pct = 100.0 * hit / total if total else 0.0
            print(f"| {dataset} | {cov_type} | {hit} | {total} | {pct:.1f} |")


if __name__ == "__main__":
    main(sys.argv[1])
