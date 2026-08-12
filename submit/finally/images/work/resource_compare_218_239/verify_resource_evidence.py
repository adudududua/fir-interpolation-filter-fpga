from __future__ import annotations

import csv
import hashlib
import json
import re
import sys
from pathlib import Path


EXPECTED = {
    "LUT218": {"LUT": 218, "FF": 365, "DSP48E1": 4, "RAMB18E1": 4},
    "LUT239": {"LUT": 239, "FF": 388, "DSP48E1": 3, "RAMB18E1": 4},
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def extract_used(report: Path, pattern: str) -> int:
    text = report.read_text(encoding="utf-8", errors="replace")
    match = re.search(pattern, text, re.MULTILINE)
    if not match:
        raise RuntimeError(f"pattern not found in {report}: {pattern}")
    return int(match.group(1))


def main() -> None:
    if len(sys.argv) != 5:
        raise SystemExit("usage: verify_resource_evidence.py <analysis_dir> <raw218> <raw239> <output.json>")
    analysis_dir, raw218, raw239, output = map(Path, sys.argv[1:])
    rows = read_rows(analysis_dir / "module_resource_distribution.csv")
    findings: list[str] = []
    totals: dict[str, dict[str, int]] = {}
    for variant in EXPECTED:
        selected = [row for row in rows if row["variant"] == variant]
        totals[variant] = {
            resource: sum(int(row[resource]) for row in selected)
            for resource in ("LUT", "FF", "DSP48E1", "RAMB18E1")
        }
        if totals[variant] != EXPECTED[variant]:
            findings.append(f"CSV total mismatch for {variant}: {totals[variant]}")

    for variant, raw_dir in (("LUT218", raw218), ("LUT239", raw239)):
        report = raw_dir / "utilization_routed.rpt"
        report_values = {
            "LUT": extract_used(report, r"\|\s*Slice LUTs\s*\|\s*(\d+)\s*\|"),
            "FF": extract_used(report, r"\|\s*Slice Registers\s*\|\s*(\d+)\s*\|"),
            "DSP48E1": extract_used(report, r"\|\s*DSPs\s*\|\s*(\d+)\s*\|"),
            "RAMB18E1": extract_used(report, r"\|\s*RAMB18\s*\|\s*(\d+)\s*\|"),
        }
        if report_values != EXPECTED[variant]:
            findings.append(f"Vivado report mismatch for {variant}: {report_values}")

    by_variant_module = {
        (row["variant"], row["module"]): row for row in rows
    }
    cic218 = by_variant_module[("LUT218", "16倍CIC插值")]
    cic239 = by_variant_module[("LUT239", "16倍CIC插值")]
    cic_delta = {
        resource: int(cic239[resource]) - int(cic218[resource])
        for resource in ("LUT", "FF", "DSP48E1", "RAMB18E1")
    }
    if cic_delta != {"LUT": 23, "FF": 23, "DSP48E1": -1, "RAMB18E1": 0}:
        findings.append(f"CIC delta mismatch: {cic_delta}")

    evidence_files = [
        analysis_dir / "module_resource_distribution.csv",
        analysis_dir / "module_resource_comparison.csv",
        analysis_dir / "physical_lut_attribution.csv",
        analysis_dir / "analysis_summary.json",
        raw218 / "primitive_cells.tsv",
        raw218 / "lut_connectivity.tsv",
        raw239 / "primitive_cells.tsv",
        raw239 / "lut_connectivity.tsv",
    ]
    result = {
        "status": "PASS" if not findings else "FAIL",
        "totals": totals,
        "cic_delta_239_minus_218": cic_delta,
        "evidence_sha256": {str(path): sha256(path) for path in evidence_files},
        "findings": findings,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if findings:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
