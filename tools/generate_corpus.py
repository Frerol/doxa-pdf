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
        f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\n"
        f"startxref\n{xref}\n%%EOF\n"
    ).encode("ascii"))
    path.write_bytes(pdf)


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
