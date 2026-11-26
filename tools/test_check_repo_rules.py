# SPDX-License-Identifier: GPL-3.0-or-later

from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from check_repo_rules import forbidden_names, violations


HEADER = "// SPDX-License-Identifier: GPL-3.0-or-later"


class RepoRulesTest(unittest.TestCase):
    def setUp(self):
        directory = TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.paths = []

    def write(self, name, contents):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(contents if isinstance(contents, bytes) else contents.encode())
        self.paths.append(name)

    def findings(self, names=(), targets=()):
        return [
            (path, line, rule)
            for path, line, rule, _ in violations(self.root, self.paths, names, targets)
        ]

    def test_spdx_accepts_shebang_and_rejects_late_or_missing_header(self):
        self.write("valid.sh", "#!/bin/sh\n" + HEADER.replace("//", "#"))
        self.write("late.kt", "\n" * 5 + HEADER)
        self.write("missing.py", "print('hello')")
        self.write("exempt.kts", "// doxa-rules: allow spdx")
        self.assertEqual(self.findings(), [
            ("late.kt", 1, "spdx"),
            ("missing.py", 1, "spdx"),
        ])

    def test_dart_rules_report_source_lines_and_allow_markdown(self):
        examples = (
            "import\n    'package:flutter/material.dart';\n"
            "final flags = FPDF_INCREMENTAL;\n"
            "class oNeEuRoFilter {}\n"
            "// One-Euro\n"
        )
        self.write("bad.dart", HEADER + "\n" + examples)
        self.write("example.md", examples)
        self.write("good.dart", HEADER + "\n"
                   "import 'package:material_ui/material_ui.dart';\n"
                   "final flags = FPDF_INCREMENTAL_TEST;\n"
                   "class ArcLengthFilter {}\n")
        self.assertEqual(self.findings(), [
            ("bad.dart", 3, "flutter-material"),
            ("bad.dart", 4, "pdfium-incremental"),
            ("bad.dart", 5, "one-euro"),
            ("bad.dart", 6, "one-euro"),
        ])

    def test_opt_out_is_specific_to_line_and_rule(self):
        self.write("example.dart", HEADER + "\n"
                   "import 'package:flutter/material.dart'; // doxa-rules: allow flutter-material\n"
                   "final OneEuro = FPDF_INCREMENTAL; // doxa-rules: allow one-euro\n"
                   "// FPDF_INCREMENTAL // doxa-rules: allow pdfium-incremental\n"
                   "// One-Euro\n")
        self.assertEqual(self.findings(), [
            ("example.dart", 3, "pdfium-incremental"),
            ("example.dart", 5, "one-euro"),
        ])

    def test_skips_generated_vendored_fixture_license_and_binary_files(self):
        for name in (
            "nested/example.g.dart", "example.g.kt", "example.g.swift",
            "nested/messages.g.h", "app/lib/l10n/gen/nested/example.dart",
            "third_party/example.dart", "test_corpus/example.dart", "LICENSE",
        ):
            self.write(name, "Acme Reader")
        self.write("binary.dart", b"Acme Reader\x00")
        self.write("invalid-utf8.dart", b"Acme Reader\xff")
        self.write("app/lib/l10n/general.dart", HEADER + "\n// Acme Reader")
        self.assertEqual(self.findings({"acme reader"}), [
            ("app/lib/l10n/general.dart", 2, "forbidden-name"),
        ])

    def test_names_from_both_sources_are_case_insensitive_literal_substrings(self):
        self.write(".forbidden-names", "  # Ghost Reader\n Local Reader \n\n")
        self.paths.remove(".forbidden-names")
        self.write("docs.md", "xACME Readerx\nBETA READER\nlocal reader\n"
                   "ToolXPlus\nTool.Plus\nGhost Reader\n"
                   "Acme Reader <!-- doxa-rules: allow forbidden-name -->\n")
        names = forbidden_names(self.root, {
            "DOXA_FORBIDDEN_NAMES": " Acme Reader, Beta Reader\nTool.Plus, ",
        })
        self.assertEqual(self.findings(names), [
            ("docs.md", line, "forbidden-name") for line in (1, 2, 3, 5, 7)
        ])

    def test_forbidden_names_also_apply_to_file_paths(self):
        self.write("docs/acme-reader-notes.md", "Notes about a commercial PDF reader.\n")
        self.assertEqual(self.findings({"acme-reader"}), [
            ("docs/acme-reader-notes.md", 0, "forbidden-name"),
        ])

    def test_scope_accepts_file_and_directory_targets(self):
        for name in ("app/file.dart", "app/sub/file.dart", "apple/file.dart",
                     "tools/one.py", "tools/two.py"):
            self.write(name, "")
        self.assertEqual(self.findings(targets=("app", "tools/one.py")), [
            (path, 1, "spdx") for path in
            ("app/file.dart", "app/sub/file.dart", "tools/one.py")
        ])
