# PDF test corpus

Use these paths relative to `test_corpus/` when reporting a spike result.
[MANIFEST](MANIFEST) records where each PDF comes from and how it is licensed.

| Spike | Fixtures |
| --- | --- |
| A · Rendering | `rotated-pages.pdf` (0°, 90°, 180°, 270°), `offset-cropbox.pdf`, `many-pages.pdf` (1,001 pages), and `external/college-physics.pdf` (1,275 pages, 102,098,884 bytes) |
| B · Ink | `rotated-pages.pdf`, `offset-cropbox.pdf`, and `marked-up-xournalpp.pdf` |
| C · Annotation writing | `two-column-article.pdf`, `rtl-cjk.pdf` (Hebrew, Japanese, Chinese and Korean), `encrypted.pdf` (user password `study`, owner password `doxa-owner`), and `annotated-*.pdf` |
| D · OCR | `scanned-300.pdf` and `external/scanned-chapter.pdf` (grayscale page images at 300 dpi with no text layer) |

The Acrobat fixture has a highlight with an appearance stream and a
linked popup. It retains the upstream file's linearization hints, which
qpdf reports as inconsistent. Okular saved a sticky note. The pdf.js editor save API added
a free-text annotation to the offset CropBox sample. Xournal++ 1.3.8
exported a pen stroke and a highlight over the two-column sample as
flattened page content. Use this export to check that editing a PDF
preserves existing page content.

## External files

From the repository root, run `tools/fetch_corpus.sh` with Bash, curl,
sha256sum and Ghostscript. The script verifies each download against the
manifest before putting it in the git-ignored `external/` directory.
The scan download retains the archive's OCR layer. The script rasterizes
Chapter I of Part I separately to provide an image-only input for Spike D.

The two PLOS Medicine articles provide published examples with
multi-column layouts and tables. The textbook is the OpenStax College
print edition of *College Physics*. Download for free at
[OpenStax](https://openstax.org/details/books/college-physics).
The textbook content is CC BY 4.0. The book's notices identify exclusions
for the OpenStax and Connexions names, logos, and the cover.

## Regenerating local samples

Run `python3 tools/generate_corpus.py` with qpdf, Ghostscript, Pango
(`pango-view`), Noto Sans Hebrew and Noto Sans CJK installed. The generator
recreates the seven Doxa-authored base samples. Some exporters record
timestamps or generate file identifiers.

The embedded font subsets in `rtl-cjk.pdf` come from
[Noto Sans Hebrew](https://github.com/notofonts/hebrew) and
[Noto Sans CJK](https://github.com/notofonts/noto-cjk).
Both fonts are available under the [SIL Open Font License 1.1](LICENSE-OFL-1.1.txt).
The Acrobat sample comes from the pdf.js test suite under
[Apache 2.0](LICENSE-Apache-2.0.txt).
