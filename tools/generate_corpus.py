#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

"""Regenerate the Doxa-authored fixtures. See test_corpus/README.md."""

from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory

CORPUS = Path(__file__).resolve().parents[1] / "test_corpus"


def stream(content):
    return b"<< /Length %d >>\nstream\n" % len(content) + content + b"\nendstream"


def text_block(x, y, lines):
    content = [f"BT /F1 14 Tf {x} {y} Td 20 TL"]
    content.extend(f"({line}) Tj T*" for line in lines)
    return "\n".join([*content, "ET"]).encode("ascii")


def write_pdf(path, content, pages):
    kids = " ".join(f"{number} 0 R" for number in range(5, 5 + len(pages)))
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        f"<< /Type /Pages /Kids [{kids}] /Count {len(pages)} >>".encode("ascii"),
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        stream(content),
    ]
    for options in pages:
        objects.append((
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
            "/Resources << /Font << /F1 3 0 R >> >> /Contents 4 0 R "
            f"{options} >>"
        ).encode("ascii"))

    serialize(path, objects)


def serialize(path, objects, info=None):
    """Write objects 1..n (object 1 is the catalog) with a classic xref."""
    pdf = bytearray(b"%PDF-1.7\n")
    offsets = []
    for number, obj in enumerate(objects, start=1):
        offsets.append(len(pdf))
        pdf.extend(f"{number} 0 obj\n".encode("ascii") + obj + b"\nendobj\n")

    xref = len(pdf)
    pdf.extend(f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode("ascii"))
    for offset in offsets:
        pdf.extend(f"{offset:010d} 00000 n \n".encode("ascii"))
    pdf.extend((
        f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R"
        + (f" /Info {info} 0 R" if info else "")
        + " >>\n"
        f"startxref\n{xref}\n%%EOF\n"
    ).encode("ascii"))
    path.write_bytes(pdf)


def write_navigation_pdf(path):
    """Outline, page labels and internal, URI and remote links (FR-VIEW-007..011, 014)."""
    page_count = 6
    page_ids = [5 + 2 * i for i in range(page_count)]
    content_ids = [6 + 2 * i for i in range(page_count)]
    labels = ["i", "ii", "1", "2", "3", "A-1"]
    next_id = 5 + 2 * page_count
    outline_root, preface, chapter, section, site = range(next_id, next_id + 5)
    link_goto, link_uri, link_remote = range(next_id + 5, next_id + 8)

    def ref(number):
        return f"{number} 0 R"

    objects = {
        1: (
            "<< /Type /Catalog /Pages 2 0 R /PageMode /UseOutlines "
            f"/Outlines {ref(outline_root)} /PageLabels << /Nums [0 << /S /r >> "
            "2 << /S /D >> 5 << /S /D /P (A-) >>] >> >>"
        ),
        2: (
            f"<< /Type /Pages /Kids [{' '.join(ref(i) for i in page_ids)}] "
            f"/Count {page_count} >>"
        ),
        3: "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        4: "<< /Title (Navigation fixture) /Author (Doxa PDF) >>",
    }
    for i, (page, content) in enumerate(zip(page_ids, content_ids)):
        annots = ""
        if i == 2:
            annots = f"/Annots [{ref(link_goto)} {ref(link_uri)} {ref(link_remote)}] "
        objects[page] = (
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
            f"/Resources << /Font << /F1 3 0 R >> >> /Contents {ref(content)} {annots}>>"
        )
        objects[content] = stream(text_block(72, 700, [
            f"Page {labels[i]}",
            "Navigation fixture for Doxa PDF.",
        ])).decode("ascii")
    objects[outline_root] = (
        f"<< /Type /Outlines /First {ref(preface)} /Last {ref(site)} /Count 4 >>"
    )
    objects[preface] = (
        f"<< /Title (Preface) /Parent {ref(outline_root)} /Next {ref(chapter)} "
        f"/Dest [{ref(page_ids[0])} /XYZ 72 720 0] >>"
    )
    objects[chapter] = (
        f"<< /Title (Chapter 1) /Parent {ref(outline_root)} /Prev {ref(preface)} "
        f"/Next {ref(site)} /First {ref(section)} /Last {ref(section)} /Count 1 "
        f"/Dest [{ref(page_ids[2])} /Fit] >>"
    )
    objects[section] = (
        f"<< /Title (Section 1.1) /Parent {ref(chapter)} "
        f"/A << /S /GoTo /D [{ref(page_ids[3])} /XYZ 72 400 2] >> >>"
    )
    objects[site] = (
        f"<< /Title (Project site) /Parent {ref(outline_root)} /Prev {ref(chapter)} "
        "/A << /S /URI /URI (https://example.org/doxa) >> >>"
    )
    objects[link_goto] = (
        "<< /Type /Annot /Subtype /Link /Rect [72 600 200 620] /Border [0 0 0] "
        f"/Dest [{ref(page_ids[5])} /XYZ 0 792 0] >>"
    )
    objects[link_uri] = (
        "<< /Type /Annot /Subtype /Link /Rect [72 560 200 580] /Border [0 0 0] "
        "/A << /S /URI /URI (https://example.org/) >> >>"
    )
    objects[link_remote] = (
        "<< /Type /Annot /Subtype /Link /Rect [72 520 200 540] /Border [0 0 0] "
        "/A << /S /GoToR /F (other.pdf) /D [0 /Fit] >> >>"
    )
    serialize(
        path, [objects[n].encode("ascii") for n in range(1, len(objects) + 1)], info=4,
    )


def write_annotations_pdf(path):
    """Three pages of annotations with known values (issue #140).

    Page 1 has Doxa's own markup and ink, a foreign underline without /NM,
    foreign ink, a square, and what Doxa leaves out or cannot draw: a popup,
    a link and a highlight with a broken /QuadPoints array. Page 2 is
    rotated by 90 degrees and page 3 has an offset CropBox; each has one
    highlight. The ids are fixed, so the file is reproducible.
    """
    doxa_markup = "doxa:0b3f6c1e-2a4d-4e8f-9a1b-3c5d7e9f1a2b"
    doxa_ink = "doxa:5e7a9c1b-3d5f-4a7c-8e9a-1b3c5d7e9fa0"
    annots = [
        # 6: Doxa highlight over the first line, with its note and text.
        "<< /Type /Annot /Subtype /Highlight /Rect [70 696 330 716] "
        "/QuadPoints [72 714 328 714 72 698 328 698] /C [1 1 0] /CA 0.4 "
        f"/NM ({doxa_markup}) /DoxaVersion (1) /DoxaText (A field notebook) "
        "/T (Ana) /Contents (Check the date) /M (D:20261127103000Z) /F 4 /Popup 11 0 R >>",
        # 7: foreign underline without /NM, two lines.
        "<< /Type /Annot /Subtype /Underline /Rect [70 656 400 696] "
        "/QuadPoints [72 694 398 694 72 678 398 678 72 674 398 674 72 658 398 658] "
        "/C [0 0 1] /F 4 >>",
        # 8: foreign ink with a border width.
        "<< /Type /Annot /Subtype /Ink /Rect [95 395 305 505] "
        "/InkList [[100 400 200 500 300 450] [100 450 150 460]] /C [1 0 0] "
        "/Border [0 0 3] /NM (other-app-ink) /F 4 >>",
        # 9: Doxa ink drawn by the highlighter, with pressure.
        "<< /Type /Annot /Subtype /Ink /Rect [95 295 305 315] "
        "/InkList [[100 300 200 310 300 305]] /C [0 1 0] /CA 0.5 /Border [0 0 8] "
        f"/NM ({doxa_ink}) /DoxaVersion (1) /DoxaTool (highlighter) "
        "/DoxaPressure (AgA) /F 4 >>",
        # 10: a square from another app.
        "<< /Type /Annot /Subtype /Square /Rect [400 100 500 200] /C [0 0 0] "
        "/NM (square-1) /F 4 >>",
        # 11: a popup, which belongs to the highlight and is left out.
        "<< /Type /Annot /Subtype /Popup /Rect [400 700 550 780] /Parent 6 0 R >>",
        # 12: a link, read by pageLinks instead.
        "<< /Type /Annot /Subtype /Link /Rect [72 100 200 120] /Border [0 0 0] "
        "/A << /S /URI /URI (https://example.org/) >> >>",
        # 13: a highlight whose /QuadPoints is not a multiple of eight.
        "<< /Type /Annot /Subtype /Highlight /Rect [70 600 300 620] "
        "/QuadPoints [72 618 298 618 72 602] /C [1 1 0] /NM (broken-quads) >>",
        # 14 (page 2) and 15 (page 3): one highlight each.
        "<< /Type /Annot /Subtype /Highlight /Rect [70 696 330 716] "
        "/QuadPoints [72 714 328 714 72 698 328 698] /C [1 0.5 0] /NM (rotated) >>",
        "<< /Type /Annot /Subtype /Highlight /Rect [70 696 330 716] "
        "/QuadPoints [72 714 328 714 72 698 328 698] /C [1 0.5 0] /NM (cropped) >>",
    ]
    content = text_block(72, 700, [
        "A field notebook",
        "The morning light crossed the valley.",
        "We drew a map and marked the river.",
    ])
    page = (
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
        "/Resources << /Font << /F1 3 0 R >> >> /Contents 4 0 R {} >>"
    )
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [5 0 R 16 0 R 17 0 R] /Count 3 >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        stream(content),
        page.format("/Annots [6 0 R 7 0 R 8 0 R 9 0 R 10 0 R 11 0 R 12 0 R 13 0 R]").encode("ascii"),
        *(annot.encode("ascii") for annot in annots),
        page.format("/Rotate 90 /Annots [14 0 R]").encode("ascii"),
        page.format("/CropBox [37.5 62.25 547.75 728.5] /Annots [15 0 R]").encode("ascii"),
    ]
    serialize(path, objects)


def main():
    sample = text_block(72, 700, [
        "A field notebook",
        "The morning light crossed the valley.",
        "We drew a map and marked the river.",
        "A reader can highlight this sentence.",
    ])
    write_pdf(CORPUS / "rotated-pages.pdf", sample, [
        "/Rotate 0", "/Rotate 90", "/Rotate 180", "/Rotate 270",
    ])
    write_pdf(CORPUS / "offset-cropbox.pdf", sample, [
        "/CropBox [37.5 62.25 547.75 728.5]",
    ])
    article = text_block(60, 732, ["Notes from a river survey"])
    article += b"\n" + text_block(60, 678, [
        "Methods",
        "We set out at dawn. Two teams",
        "walked along opposite banks.",
        "Each team recorded water depth",
        "at five equally spaced sites.",
    ])
    article += b"\n" + text_block(320, 678, [
        "Results",
        "The river was deeper on the",
        "west side near the bend. At",
        "the last site both banks had",
        "similar measured depths.",
    ])
    write_pdf(CORPUS / "two-column-article.pdf", article, [""])
    write_pdf(CORPUS / "many-pages.pdf", sample, [""] * 1001)
    write_navigation_pdf(CORPUS / "navigation.pdf")
    write_annotations_pdf(CORPUS / "annotations.pdf")

    markup = (
        '<span font_family="Noto Sans Hebrew">שלום עולם</span>\n\n'
        '<span font_family="Noto Sans CJK JP">日本語の読書</span>\n'
        '<span font_family="Noto Sans CJK SC">中文学习</span>\n'
        '<span font_family="Noto Sans CJK KR">한국어 공부</span>'
    )
    subprocess.run([
        "pango-view", "--no-display", "--pixels", "--margin=48",
        "--font=20", "--markup", f"--text={markup}",
        f"--output={CORPUS / 'rtl-cjk.pdf'}",
    ], check=True)

    with TemporaryDirectory(prefix="doxa-corpus-") as scratch:
        plain = Path(scratch) / "plain.pdf"
        write_pdf(plain, sample, [""])
        subprocess.run([
            "qpdf", "--encrypt", "study", "doxa-owner", "256", "--",
            plain, CORPUS / "encrypted.pdf",
        ], check=True)
        subprocess.run([
            "gs", "-q", "-dBATCH", "-dNOPAUSE", "-dSAFER",
            "-sDEVICE=pdfimage8", "-r300", "-sCompression=Flate",
            f"-sOutputFile={CORPUS / 'scanned-300.pdf'}", plain,
        ], check=True)


if __name__ == "__main__":
    main()
