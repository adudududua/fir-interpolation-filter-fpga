from __future__ import annotations

import csv
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path


MODULE_BY_FILE = {
    "interp2_stage1_single_bram_serial_ce.v": "FIR1级",
    "nf_stage1_history_ramb18_sdp.v": "FIR1级",
    "interp2_stage23_lutram_cic_dsp_ce.v": "FIR2/3级",
    "nf_stage23_history_ramb18_sdp.v": "FIR2/3级",
    "nf_unified_fir_coeff_bram.v": "FIR共享系数存储",
    "bridge_valid_quantized_to_interp2_ce.v": "2→4倍桥接量化",
    "round_sat_shift_compact.v": "2→4倍桥接量化",
    "cic_interp16_n3_hold2_dsp_ce.v": "16倍CIC插值",
    "dual_rate_test_tone_rom_source.v": "测试音频ROM",
    "demo_interp_dac8_audio_pcm_common.v": "音频公共封装/DAC",
    "matrix_keypad_mode_ctrl_ultracompact.v": "按键与模式控制",
    "nf_mode_cdc_handshake.v": "按键与模式控制",
    "dual_family_audio_clock.v": "时钟管理",
    "board_demo_competition_dac8_top.v": "板级顶层控制",
}

CORE_MODULES = {
    "FIR1级",
    "FIR2/3级",
    "FIR共享系数存储",
    "2→4倍桥接量化",
    "16倍CIC插值",
}

MODULE_ORDER = [
    "FIR1级",
    "FIR2/3级",
    "FIR共享系数存储",
    "2→4倍桥接量化",
    "16倍CIC插值",
    "滤波器核心跨级/共享逻辑",
    "核心—外围接口共享逻辑",
    "测试音频ROM",
    "音频公共封装/DAC",
    "按键与模式控制",
    "时钟管理",
    "板级顶层控制",
    "外围跨模块共享逻辑",
    "来源不可恢复逻辑",
]


def module_for_file(file_name: str) -> str | None:
    if not file_name:
        return None
    return MODULE_BY_FILE.get(Path(file_name).name)


def read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def parse_connection_modules(value: str) -> set[str]:
    modules: set[str] = set()
    for record in value.split(";"):
        if not record:
            continue
        fields = record.split("|", 2)
        if len(fields) < 3:
            continue
        module = module_for_file(fields[2])
        if module:
            modules.add(module)
    return modules


def classify_modules(modules: set[str]) -> str:
    if len(modules) == 1:
        return next(iter(modules))
    if not modules:
        return "来源不可恢复逻辑"
    core_members = modules & CORE_MODULES
    if core_members and modules <= CORE_MODULES:
        return "滤波器核心跨级/共享逻辑"
    if core_members:
        return "核心—外围接口共享逻辑"
    return "外围跨模块共享逻辑"


def refine_shared_classification(classification: str, modules: set[str]) -> str:
    if classification == "滤波器核心跨级/共享逻辑" and modules == {"FIR1级"}:
        return "FIR1级"
    if classification == "滤波器核心跨级/共享逻辑" and modules == {"FIR2/3级"}:
        return "FIR2/3级"
    if (
        classification == "滤波器核心跨级/共享逻辑"
        and modules == {"16倍CIC插值", "FIR2/3级"}
    ):
        # These LUTs lie on the Stage3-to-CIC interface.  The version delta
        # is caused by CIC_INTEGRATOR_DSP_MODE, so the comparison view assigns
        # them to the CIC mapping while retaining the endpoint set in the
        # evidence CSV.
        return "16倍CIC插值"
    return classification


def lut_site_key(row: dict[str, str]) -> str:
    match = re.search(r"\.([ABCD])(?:5|6)LUT$", row["BEL"])
    if not match:
        raise ValueError(f"Cannot derive physical LUT BEL from {row['CELL']}: {row['BEL']}")
    return f"{row['LOC']}/{match.group(1)}LUT"


def resource_distribution(
    variant: str,
    raw_dir: Path,
    expected: dict[str, int],
) -> tuple[list[dict[str, int | str]], list[dict[str, str]], dict[str, int]]:
    primitives = read_tsv(raw_dir / "primitive_cells.tsv")
    connectivity = {row["CELL"]: row for row in read_tsv(raw_dir / "lut_connectivity.tsv")}

    counts: dict[str, Counter[str]] = defaultdict(Counter)
    lut_details: list[dict[str, str]] = []
    lut_groups: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in primitives:
        if row["PRIMITIVE_GROUP"] == "LUT":
            lut_groups[lut_site_key(row)].append(row)

    for site_key, rows in sorted(lut_groups.items()):
        direct_modules = {
            module
            for row in rows
            if (module := module_for_file(row["FILE_NAME"])) is not None
        }
        endpoint_modules: set[str] = set()
        for row in rows:
            connection = connectivity[row["CELL"]]
            endpoint_modules |= parse_connection_modules(connection["STARTPOINT_CELLS"])
            endpoint_modules |= parse_connection_modules(connection["ENDPOINT_CELLS"])
        evidence_modules = direct_modules if direct_modules else endpoint_modules
        classification = refine_shared_classification(
            classify_modules(evidence_modules), evidence_modules
        )
        counts[classification]["LUT"] += 1
        lut_details.append(
            {
                "variant": variant,
                "physical_lut": site_key,
                "primitive_cells": ";".join(sorted(row["CELL"] for row in rows)),
                "direct_modules": ";".join(sorted(direct_modules)),
                "endpoint_modules": ";".join(sorted(endpoint_modules)),
                "classification": classification,
            }
        )

    for row in primitives:
        primitive_group = row["PRIMITIVE_GROUP"]
        if primitive_group == "LUT":
            continue
        module = module_for_file(row["FILE_NAME"]) or "来源不可恢复逻辑"
        if primitive_group == "FLOP_LATCH":
            # The system headline reports Slice Registers. Eight DAC output
            # registers are packed into OLOGIC and are therefore excluded.
            if row["LOC"].startswith("SLICE_"):
                counts[module]["FF"] += 1
        elif primitive_group == "MULT":
            counts[module]["DSP48E1"] += 1
        elif primitive_group == "BMEM":
            counts[module]["RAMB18E1"] += 1

    rows_out: list[dict[str, int | str]] = []
    for module in MODULE_ORDER:
        counter = counts[module]
        if not counter:
            continue
        rows_out.append(
            {
                "variant": variant,
                "module": module,
                "LUT": counter["LUT"],
                "FF": counter["FF"],
                "DSP48E1": counter["DSP48E1"],
                "RAMB18E1": counter["RAMB18E1"],
            }
        )

    totals = {
        resource: sum(int(row[resource]) for row in rows_out)
        for resource in ("LUT", "FF", "DSP48E1", "RAMB18E1")
    }
    if totals != expected:
        raise RuntimeError(f"{variant} totals mismatch: {totals} != {expected}")
    return rows_out, lut_details, totals


def write_csv(path: Path, rows: list[dict], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    if len(sys.argv) not in (4, 5):
        raise SystemExit(
            "usage: analyze_resource_distribution.py <lut218_raw> <lut239_raw> "
            "<output_dir> [board|ooc]"
        )
    raw_218 = Path(sys.argv[1])
    raw_239 = Path(sys.argv[2])
    output_dir = Path(sys.argv[3])
    scope = sys.argv[4] if len(sys.argv) == 5 else "board"
    expected_by_scope = {
        "board": {
            "LUT218": {"LUT": 218, "FF": 365, "DSP48E1": 4, "RAMB18E1": 4},
            "LUT239": {"LUT": 239, "FF": 388, "DSP48E1": 3, "RAMB18E1": 4},
        },
        "ooc": {
            "LUT218": {"LUT": 190, "FF": 279, "DSP48E1": 4, "RAMB18E1": 3},
            "LUT239": {"LUT": 212, "FF": 302, "DSP48E1": 3, "RAMB18E1": 3},
        },
    }
    if scope not in expected_by_scope:
        raise SystemExit("scope must be board or ooc")

    dist_218, details_218, totals_218 = resource_distribution(
        "LUT218", raw_218, expected_by_scope[scope]["LUT218"]
    )
    dist_239, details_239, totals_239 = resource_distribution(
        "LUT239", raw_239, expected_by_scope[scope]["LUT239"]
    )
    write_csv(
        output_dir / "module_resource_distribution.csv",
        dist_218 + dist_239,
        ["variant", "module", "LUT", "FF", "DSP48E1", "RAMB18E1"],
    )
    write_csv(
        output_dir / "physical_lut_attribution.csv",
        details_218 + details_239,
        ["variant", "physical_lut", "primitive_cells", "direct_modules", "endpoint_modules", "classification"],
    )

    by_variant = {
        "LUT218": {str(row["module"]): row for row in dist_218},
        "LUT239": {str(row["module"]): row for row in dist_239},
    }
    comparison = []
    for module in MODULE_ORDER:
        row_218 = by_variant["LUT218"].get(module, {})
        row_239 = by_variant["LUT239"].get(module, {})
        comparison.append(
            {
                "module": module,
                "LUT218_LUT": int(row_218.get("LUT", 0)),
                "LUT239_LUT": int(row_239.get("LUT", 0)),
                "delta_239_minus_218_LUT": int(row_239.get("LUT", 0)) - int(row_218.get("LUT", 0)),
                "LUT218_FF": int(row_218.get("FF", 0)),
                "LUT239_FF": int(row_239.get("FF", 0)),
                "delta_239_minus_218_FF": int(row_239.get("FF", 0)) - int(row_218.get("FF", 0)),
                "LUT218_DSP": int(row_218.get("DSP48E1", 0)),
                "LUT239_DSP": int(row_239.get("DSP48E1", 0)),
                "delta_239_minus_218_DSP": int(row_239.get("DSP48E1", 0)) - int(row_218.get("DSP48E1", 0)),
                "LUT218_RAMB18": int(row_218.get("RAMB18E1", 0)),
                "LUT239_RAMB18": int(row_239.get("RAMB18E1", 0)),
                "delta_239_minus_218_RAMB18": int(row_239.get("RAMB18E1", 0)) - int(row_218.get("RAMB18E1", 0)),
            }
        )
    write_csv(
        output_dir / "module_resource_comparison.csv",
        comparison,
        list(comparison[0]),
    )

    summary = {
        "method": {
            "tool": "Vivado 2025.2 routed checkpoint",
            "scope": scope,
            "lut_unit": "unique physical LUT BEL (A/B/C/D LUT per slice); O5/O6 primitives merged",
            "ff_unit": "Slice Register only; OLOGIC output registers excluded to match report_utilization",
            "attribution": "RTL source location, then register/DSP/BRAM connectivity for flattened LUTs",
            "shared_logic": "kept as an explicit cross-module class rather than assigned arbitrarily",
        },
        "totals": {"LUT218": totals_218, "LUT239": totals_239},
        "comparison": comparison,
    }
    (output_dir / "analysis_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
