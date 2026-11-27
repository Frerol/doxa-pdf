# SPDX-License-Identifier: GPL-3.0-or-later

"""Tests for build_dictionary_catalog.py on packs written for these tests."""

import hashlib
import json
import tempfile
import unittest
import zipfile
from pathlib import Path

import build_dictionary_catalog as bc

PACKS = [{"id": "doxa-xx", "file": "doxa-xx.zip", "name": "Test", "language": "xx"}]
IFO = b"StarDict's dict ifo file\nversion=3.0.0\nbookname=Test book\nwordcount=1\n"


def write_pack(folder: Path, ifo: bytes = IFO, files=("doxa-xx.idx", "doxa-xx.dict.dz")) -> Path:
    archive = folder / "doxa-xx.zip"
    with zipfile.ZipFile(archive, "w") as z:
        z.writestr("doxa-xx/doxa-xx.ifo", ifo)
        for name in files:
            z.writestr(f"doxa-xx/{name}", b"x" * 10)
        z.writestr("doxa-xx/LICENSE.txt", b"licence")
    return archive


class CatalogTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.dir = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def test_lists_what_the_app_checks(self):
        archive = write_pack(self.dir)
        catalog = bc.build(self.dir, PACKS)
        self.assertEqual(catalog["format"], 1)
        pack = catalog["packs"][0]
        self.assertEqual(pack["url"], "doxa-xx.zip")
        self.assertNotIn("file", pack)
        self.assertEqual(pack["bookName"], "Test book")
        self.assertEqual(pack["sha256"], hashlib.sha256(archive.read_bytes()).hexdigest())
        self.assertEqual(pack["size"], archive.stat().st_size)
        self.assertEqual(pack["unpackedSize"], len(IFO) + 10 + 10 + len(b"licence"))
        self.assertEqual(pack["ifoSha256"], hashlib.sha256(IFO).hexdigest())

    def test_refuses_a_pack_the_app_could_not_open(self):
        write_pack(self.dir, files=("doxa-xx.idx",))
        with self.assertRaisesRegex(bc.PackError, r"no \.dict"):
            bc.build(self.dir, PACKS)
        write_pack(self.dir, ifo=b"StarDict's dict ifo file\nversion=3.0.0\n")
        with self.assertRaisesRegex(bc.PackError, "bookname"):
            bc.build(self.dir, PACKS)
        (self.dir / "doxa-xx.zip").unlink()
        with self.assertRaisesRegex(bc.PackError, "missing"):
            bc.build(self.dir, PACKS)

    def test_check_finds_a_pack_rebuilt_after_the_catalogue(self):
        write_pack(self.dir)
        catalog = self.dir / "dictionaries.json"
        listing = self.dir / "packs.json"
        listing.write_text(json.dumps({"packs": PACKS}))
        self.assertEqual(bc.main(["--packs", str(self.dir), "--list", str(listing), "--out", str(catalog)]), 0)
        self.assertEqual(bc.check(self.dir, PACKS, catalog), [])

        write_pack(self.dir, ifo=IFO + b"description=new build\n")
        problems = bc.check(self.dir, PACKS, catalog)
        self.assertTrue(any("sha256" in p for p in problems), problems)
        self.assertTrue(any("ifoSha256" in p for p in problems), problems)

    def test_the_committed_pack_list_is_valid(self):
        packs = json.loads(bc.PACKS.read_text(encoding="utf-8"))["packs"]
        self.assertTrue(packs)
        ids = [p["id"] for p in packs]
        self.assertEqual(len(ids), len(set(ids)))
        for pack in packs:
            for key in ("id", "file", "name", "language", "source", "licence"):
                self.assertTrue(pack.get(key), (pack, key))
            self.assertEqual(pack.get("kind", "definitions"), "definitions")


if __name__ == "__main__":
    unittest.main()
