from __future__ import annotations

import csv
import hashlib
import json
import re
import sys
from pathlib import Path


def parse_summary(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
    return values


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def parse_boundary_timing(path: Path) -> dict[str, float | int]:
    text = path.read_text(encoding="utf-8", errors="replace")
    match = re.search(
        r"^\s*([-+]?\d+\.\d+)\s+([-+]?\d+\.\d+)\s+(\d+)\s+\d+\s+"
        r"([-+]?\d+\.\d+)\s+([-+]?\d+\.\d+)\s+(\d+)\s+\d+",
        text,
        flags=re.MULTILINE,
    )
    if not match:
        raise RuntimeError(f"Could not parse boundary timing summary: {path}")
    return {
        "boundary_WNS_ns": float(match.group(1)),
        "boundary_TNS_ns": float(match.group(2)),
        "boundary_setup_failing_endpoints": int(match.group(3)),
        "boundary_WHS_ns": float(match.group(4)),
        "boundary_THS_ns": float(match.group(5)),
        "boundary_hold_failing_endpoints": int(match.group(6)),
    }


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: build_matched_ooc_evidence.py <matched_ooc_dir> <output_dir>")
    base = Path(sys.argv[1])
    output = Path(sys.argv[2])
    output.mkdir(parents=True, exist_ok=True)
    runs = {
        "LUT218": [base / "results/lut218_mode2", base / "results/lut218_mode2_repeat"],
        "LUT239": [base / "results/lut239_mode1", base / "results/lut239_mode1_repeat"],
    }
    expected = {
        "LUT218": {"mode": 2, "LUT": 190, "FF": 279, "DSP48E1": 4, "RAMB18E1": 3},
        "LUT239": {"mode": 1, "LUT": 212, "FF": 302, "DSP48E1": 3, "RAMB18E1": 3},
    }
    records: list[dict[str, object]] = []
    evidence_hashes: dict[str, str] = {}
    for variant, directories in runs.items():
        normalized = []
        for index, directory in enumerate(directories, start=1):
            summary_path = directory / "core_ooc_summary.txt"
            summary = parse_summary(summary_path)
            boundary_timing_path = directory / "timing_post_route_with_ooc_boundaries.rpt"
            record = {
                "variant": variant,
                "run": index,
                "cic_dsp_mode": int(summary["CIC_INTEGRATOR_DSP_MODE"]),
                "LUT": int(summary["POST_ROUTE_LUT"]),
                "FF": int(summary["POST_ROUTE_FF"]),
                "DSP48E1": int(summary["POST_ROUTE_DSP48E1"]),
                "RAMB18E1": int(summary["POST_ROUTE_RAMB18E1"]),
                "internal_WNS_ns": float(summary["INTERNAL_WNS_NS"]),
                "internal_WHS_ns": float(summary["INTERNAL_WHS_NS"]),
                "DRC_errors": int(summary["POST_ROUTE_DRC_ERRORS"]),
            }
            record.update(parse_boundary_timing(boundary_timing_path))
            normalized.append(record)
            records.append(record)
            evidence_hashes[str(summary_path)] = sha256(summary_path)
            evidence_hashes[str(directory / "utilization_post_route.rpt")] = sha256(
                directory / "utilization_post_route.rpt"
            )
            evidence_hashes[str(boundary_timing_path)] = sha256(boundary_timing_path)
        comparable = [
            {key: value for key, value in record.items() if key not in {"run"}}
            for record in normalized
        ]
        if comparable[0] != comparable[1]:
            raise RuntimeError(f"{variant} repeat mismatch: {comparable}")
        reference = normalized[0]
        for resource in ("LUT", "FF", "DSP48E1", "RAMB18E1"):
            if reference[resource] != expected[variant][resource]:
                raise RuntimeError(f"{variant} {resource} mismatch")
        if reference["cic_dsp_mode"] != expected[variant]["mode"]:
            raise RuntimeError(f"{variant} mode mismatch")
        if reference["DRC_errors"] != 0 or reference["internal_WNS_ns"] < 0 or reference["internal_WHS_ns"] < 0:
            raise RuntimeError(f"{variant} implementation gate failed")
        if (
            reference["boundary_setup_failing_endpoints"] != 0
            or reference["boundary_hold_failing_endpoints"] != 1
            or reference["boundary_WHS_ns"] != -0.845
        ):
            raise RuntimeError(f"{variant} unexpected OOC boundary timing state")

    with (output / "matched_ooc_repeated_runs.csv").open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(records[0]))
        writer.writeheader()
        writer.writerows(records)

    official = {variant: records[0 if variant == "LUT218" else 2] for variant in runs}
    comparison = {
        "core_ooc_239_minus_218": {
            resource: int(official["LUT239"][resource]) - int(official["LUT218"][resource])
            for resource in ("LUT", "FF", "DSP48E1", "RAMB18E1")
        },
        "board_239_minus_218": {"LUT": 21, "FF": 23, "DSP48E1": -1, "RAMB18E1": 0},
    }
    result = {
        "status": "RESOURCE_AND_REPEATABILITY_PASS_WITH_DISCLOSED_OOC_BOUNDARY_HOLD",
        "method": "matched Vivado 2025.2 OOC post-route from immutable board-pass tag snapshots",
        "timing_scope_note": (
            "Internal register-to-register paths meet timing. Under the identical zero-I/O-delay "
            "standalone boundary model, each variant has one stage3_compensated_mode input-to-register "
            "hold violation at -0.845 ns; complete interface timing is taken from the signed-off board runs."
        ),
        "top": "interp128_all2x_v7_folded_fir_cic_top_ce",
        "part": "xc7a35tfgg484-2",
        "clock_MHz": 6.144,
        "official": official,
        "comparison": comparison,
        "repeat_runs": records,
        "evidence_sha256": evidence_hashes,
    }
    if comparison["core_ooc_239_minus_218"] != {"LUT": 22, "FF": 23, "DSP48E1": -1, "RAMB18E1": 0}:
        raise RuntimeError("Unexpected matched OOC delta")
    (output / "matched_ooc_evidence.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
