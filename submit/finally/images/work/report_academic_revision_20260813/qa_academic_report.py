from __future__ import annotations

import argparse
import hashlib
import json
import re
import zipfile
from pathlib import Path

from docx import Document
from docx.oxml.ns import qn


def sha256(path: Path) -> str:
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    return digest


def count_drawings(doc: Document) -> int:
    return len(doc.element.body.findall(".//" + qn("w:drawing")))


def chapter_block(doc: Document, chapter: int, next_chapter: int):
    paragraphs = list(doc.paragraphs)
    start = next(i for i, p in enumerate(paragraphs) if p.style.name == "Heading 1" and p.text.startswith(f"第{chapter}章"))
    stop = next(i for i, p in enumerate(paragraphs) if p.style.name == "Heading 1" and p.text.startswith(f"第{next_chapter}章"))
    return paragraphs[start:stop]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("docx", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    doc = Document(args.docx)
    paragraphs = list(doc.paragraphs)
    all_text = "\n".join(p.text for p in paragraphs)
    table_text = "\n".join(cell.text for table in doc.tables for row in table.rows for cell in row.cells)
    searchable = all_text + "\n" + table_text

    chapter8 = chapter_block(doc, 8, 9)
    chapter9 = chapter_block(doc, 9, 10)
    headings8 = [p.text.strip() for p in chapter8 if p.style.name.startswith("Heading")]
    headings9 = [p.text.strip() for p in chapter9 if p.style.name.startswith("Heading")]
    captions8 = [p.text.strip() for p in chapter8 if p.style.name == "Caption"]
    captions9 = [p.text.strip() for p in chapter9 if p.style.name == "Caption"]
    expected8 = [
        "第8章 历史厂商IP基线与手写RTL的口径化比较",
        "8.1 比较目的与对象",
        "8.2 统一比较口径与证据边界",
        "8.3 历史IP与手写RTL的同口径结果",
        "8.3.1 155抽头4倍前级",
        "8.3.2 七级2倍FIR完整链",
        "8.3.3 FIR—CIC路线的跨版本参照",
        "8.4 结果讨论与适用边界",
        "8.5 本章小结",
    ]
    expected9 = [
        "第9章 架构演进、资源权衡与实现选择",
        "9.1 评价准则与证据层级",
        "9.2 候选架构的横向比较",
        "9.2.1 结构与性能",
        "9.2.2 资源口径与适用条件",
        "9.3 架构演进与实现优化",
        "9.3.1 从全FIR到FIR—CIC",
        "9.3.2 Vivado 2025.2同工具链演进",
        "9.3.3 DSP—LUT权衡与优化边界",
        "9.4 同口径资源审计与版本取舍",
        "9.4.1 218/239版本的核心OOC与完整系统比较",
        "9.4.2 版本适用范围与实现选择",
    ]
    expected_captions8 = [f"表8-{i}" for i in range(1, 5)]
    expected_table9 = [f"表9-{i}" for i in range(1, 9)]
    expected_figure9 = [f"图9-{i}" for i in range(1, 5)]

    checks = {}
    checks["chapter8_heading_sequence"] = headings8 == expected8
    checks["chapter9_heading_sequence"] = headings9 == expected9
    checks["chapter8_caption_sequence"] = [caption.split()[0] for caption in captions8] == expected_captions8
    checks["chapter9_table_sequence"] = [caption.split()[0] for caption in captions9 if caption.startswith("表9-")] == expected_table9
    checks["chapter9_figure_sequence"] = [caption.split()[0] for caption in captions9 if caption.startswith("图9-")] == expected_figure9
    checks["review_heading_present"] = all_text.count("1.4 国内外研究进展与本文技术定位") >= 2
    reference_heading = next(i for i, p in enumerate(paragraphs) if p.style.name == "Heading 1" and p.text == "参考文献")
    body_before_references = "\n".join(p.text for p in paragraphs[:reference_heading])
    cited_numbers = set()
    for match in re.finditer(r"\[([0-9,\-]+)\]", body_before_references):
        for part in match.group(1).split(","):
            if "-" in part:
                start, end = (int(value) for value in part.split("-", 1))
                cited_numbers.update(range(start, end + 1))
            else:
                cited_numbers.add(int(part))
    checks["all_references_cited"] = cited_numbers.issuperset(range(1, 19))
    normalized_searchable = re.sub(r"\s+", " ", searchable)
    checks["matched_ooc_numbers"] = all(value in normalized_searchable for value in (
        "190 LUT / 279 FF 4 DSP / 3 RAMB18E1",
        "212 LUT / 302 FF 3 DSP / 3 RAMB18E1",
        "+22 LUT / +23 FF −1 DSP / 0 RAMB18E1",
        "+21 LUT / +23 FF −1 DSP / 0 RAMB18E1",
    ))
    checks["ooc_hold_disclosed"] = "−0.845 ns端口到寄存器保持时间违例" in all_text
    checks["three_endpoints_named"] = all(value in all_text for value in ("218 LUT/4 DSP", "239 LUT/3 DSP", "268 LUT/2 DSP"))
    checks["removed_old_headings"] = all(fragment not in all_text for fragment in ("8.3 ABC 三组对比", "9.3 Phase 4～Phase 7纵向迭代", "9.4.5 最终配置"))
    checks["no_old_chapter_captions"] = all(fragment not in all_text for fragment in ("表8-10", "表9-18", "图9-7"))

    with zipfile.ZipFile(args.docx, "r") as archive:
        checks["zip_integrity"] = archive.testzip() is None
        document_xml = archive.read("word/document.xml").decode("utf-8")
        settings_xml = archive.read("word/settings.xml").decode("utf-8")
        checks["toc_field_present"] = 'TOC \\o "1-2"' in document_xml
        checks["update_fields_true"] = '<w:updateFields w:val="true"' in settings_xml
        # Only count real bookmarkStart elements.  Hyperlink anchors and
        # PAGEREF field text are references, not valid bookmark definitions.
        toc_bookmarks = re.findall(
            r'<w:bookmarkStart\b[^>]*\bw:name="(_Toc[^"]+)"',
            document_xml,
        )
        pagerefs = re.findall(r'PAGEREF (_Toc\S+)', document_xml)

    checks["drawing_count_preserved_or_reduced"] = count_drawings(doc) == 50
    checks["toc_bookmark_unique"] = len(toc_bookmarks) == len(set(toc_bookmarks))
    missing_pageref_targets = sorted(set(target for target in pagerefs if target not in set(toc_bookmarks)))
    checks["pageref_targets_exist"] = not missing_pageref_targets
    revised_toc_bookmarks = [f"_TocAcademicRevision89{i:02d}" for i in range(11)]
    checks["revised_toc_bookmarks_present"] = all(
        target in set(toc_bookmarks) for target in revised_toc_bookmarks
    )

    result = {
        "status": "PASS" if all(checks.values()) else "FAIL",
        "path": str(args.docx),
        "sha256": sha256(args.docx),
        "paragraphs": len(paragraphs),
        "tables": len(doc.tables),
        "drawings": count_drawings(doc),
        "chapter8_characters": sum(len(p.text) for p in chapter8),
        "chapter9_characters": sum(len(p.text) for p in chapter9),
        "chapter8_headings": headings8,
        "chapter9_headings": headings9,
        "chapter8_captions": captions8,
        "chapter9_captions": captions9,
        "checks": checks,
        "missing_pageref_targets": missing_pageref_targets,
        "revised_toc_bookmarks": revised_toc_bookmarks,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if result["status"] != "PASS":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
