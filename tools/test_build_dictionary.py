# SPDX-License-Identifier: GPL-3.0-or-later

"""Tests for build_dictionary.py on small samples written for these tests."""

import gzip
import json
import struct
import tempfile
import unittest
import zlib
from pathlib import Path

import build_dictionary as bd

# Wiktextract-shaped records written for this test, not taken from Wiktionary.
RECORDS = [
    {
        "word": "ação",
        "lang_code": "pt",
        "pos": "noun",
        "senses": [
            {"glosses": ["ato de agir"], "examples": [{"text": "Uma boa ação."}]},
            {"glosses": ["processo", "processo judicial <civil>"]},
        ],
        "forms": [
            {"form": "ações", "tags": ["plural"]},
            {"form": "f", "tags": ["table-tags"]},
        ],
        "translations": [],
    },
    {
        "word": "Ação",
        "lang_code": "pt",
        "pos": "name",
        "senses": [{"glosses": ["nome de exemplo"]}],
    },
    {"word": "abacate", "lang_code": "pt", "pos": "noun", "senses": [{"glosses": ["fruto"]}]},
    {"word": "zebra", "lang_code": "pt", "pos": "noun", "senses": [{"glosses": ["animal"]}]},
    {"word": "Zebra", "lang_code": "pt", "pos": "name", "senses": [{"glosses": ["marca"]}]},
    {"word": "a", "lang_code": "pt", "pos": "article", "senses": [{"glosses": ["artigo"]}],
     "forms": [{"form": "abacate", "tags": []}]},
    {"word": "no gloss", "lang_code": "pt", "pos": "noun", "senses": [{"tags": ["x"]}]},
    {"word": "dog", "lang_code": "en", "pos": "noun", "senses": [{"glosses": ["animal"]}],
     "forms": [{"form": "dogs", "tags": ["plural"]}],
     "translations": [
         {"lang_code": "pt", "word": "cão", "sense": "animal"},
         {"code": "pt", "word": "cachorro", "sense": "animal"},
         {"lang_code": "pt", "word": "cão", "sense": "animal"},
         {"lang_code": "fr", "word": "chien", "sense": "animal"},
     ]},
]

OEWN = """<?xml version="1.0" encoding="UTF-8"?>
<LexicalResource>
 <Lexicon id="oewn" label="Sample" language="en" email="x" license="x" version="1">
  <LexicalEntry id="e-run-v"><Lemma writtenForm="run" partOfSpeech="v"/>
   <Form writtenForm="ran"/><Sense id="s1" synset="ss-run"/><Sense id="s2" synset="ss-flow"/></LexicalEntry>
  <LexicalEntry id="e-sprint-v"><Lemma writtenForm="sprint" partOfSpeech="v"/>
   <Sense id="s3" synset="ss-run"/></LexicalEntry>
  <Synset id="ss-run" partOfSpeech="v"><Definition>move fast on foot</Definition>
   <Example>she runs every day</Example></Synset>
  <Synset id="ss-flow" partOfSpeech="v"><Definition>flow &lt;like water&gt;</Definition></Synset>
 </Lexicon>
</LexicalResource>
"""


def parse_idx(data):
    entries, i = [], 0
    while i < len(data):
        end = data.index(b"\0", i)
        offset, size = struct.unpack(">II", data[end + 1 : end + 9])
        entries.append((data[i:end].decode(), offset, size))
        i = end + 9
    return entries


def parse_syn(data):
    pairs, i = [], 0
    while i < len(data):
        end = data.index(b"\0", i)
        pairs.append((data[i:end].decode(), struct.unpack(">I", data[end + 1 : end + 5])[0]))
        i = end + 5
    return pairs


def chunks_of(dz):
    """The chunks of a dictzip stream, each inflated on its own."""
    flags = dz[3]
    xlen = struct.unpack("<H", dz[10:12])[0]
    extra = dz[12 : 12 + xlen]
    assert flags & 0x04 and extra[:2] == b"RA"
    ver, chlen, count = struct.unpack("<HHH", extra[4:10])
    sizes = struct.unpack(f"<{count}H", extra[10 : 10 + 2 * count])
    pos = 12 + xlen
    if flags & 0x08:
        pos = dz.index(b"\0", pos) + 1
    out = []
    for size in sizes:
        inflater = zlib.decompressobj(-15)
        out.append(inflater.decompress(dz[pos : pos + size]))
        pos += size
    return ver, chlen, out


class BuildDictionaryTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.jsonl = self.tmp / "sample.jsonl.gz"
        with gzip.open(self.jsonl, "wt", encoding="utf-8") as f:
            for record in RECORDS:
                f.write(json.dumps(record, ensure_ascii=False) + "\n")

    def build_pt(self):
        glossary = bd.read_wiktextract(self.jsonl, "pt")
        return bd.build(glossary, "pt", "Sample", "two\nlines")

    def test_headwords_follow_stardict_order(self):
        words = [w for w, _, _ in parse_idx(self.build_pt().files["pt.idx"])]
        # ASCII case folds first, then bytes; "ç"/"ã" sort as their UTF-8 bytes.
        self.assertEqual(words, ["a", "abacate", "Ação", "ação", "Zebra", "zebra"])
        keys = [bd.stardict_key(w.encode()) for w in words]
        self.assertEqual(keys, sorted(keys))

    def test_definitions_are_escaped_html_at_their_offsets(self):
        built = self.build_pt()
        data = gzip.decompress(built.files["pt.dict.dz"])
        entries = {w: data[o : o + s].decode() for w, o, s in parse_idx(built.files["pt.idx"])}
        self.assertIn("<li>ato de agir<br><i>Uma boa ação.</i></li>", entries["ação"])
        self.assertIn("<i>processo:</i> processo judicial &lt;civil&gt;", entries["ação"])
        self.assertNotIn("no gloss", entries)

    def test_forms_become_synonyms_unless_they_are_headwords(self):
        built = self.build_pt()
        words = [w for w, _, _ in parse_idx(built.files["pt.idx"])]
        synonyms = parse_syn(built.files["pt.syn"])
        self.assertEqual([(a, words[o]) for a, o in synonyms], [("ações", "ação")])
        info = built.files["pt.ifo"].decode()
        self.assertIn("synwordcount=1\n", info)
        self.assertIn(f"idxfilesize={len(built.files['pt.idx'])}\n", info)
        self.assertIn("description=two lines\n", info)

    def test_dictzip_chunks_inflate_alone(self):
        glossary = bd.Glossary()
        for i in range(3000):
            glossary.add(f"w{i:05}", f"<p>{i * 7919 % 100003:x} {'é' * (i % 50)}</p>")
        built = bd.build(glossary, "big", "Big", "")
        dz = built.files["big.dict.dz"]
        ver, chlen, chunks = chunks_of(dz)
        self.assertEqual((ver, chlen), (1, bd.DICTZIP_CHUNK))
        self.assertGreater(len(chunks), 1)
        self.assertTrue(all(len(c) == chlen for c in chunks[:-1]))
        self.assertEqual(b"".join(chunks), gzip.decompress(dz))

    def test_translations_into_a_language(self):
        glossary = bd.read_translations(self.jsonl, "pt")
        built = bd.build(glossary, "en-pt", "Sample", "")
        data = gzip.decompress(built.files["en-pt.dict.dz"])
        [(word, offset, size)] = parse_idx(built.files["en-pt.idx"])
        self.assertEqual(word, "dog")
        self.assertIn("<i>animal:</i> cão, cachorro</li>", data[offset : offset + size].decode())
        self.assertEqual(parse_syn(built.files["en-pt.syn"]), [("dogs", 0)])

    def test_open_english_wordnet(self):
        path = self.tmp / "oewn.xml"
        path.write_text(OEWN, encoding="utf-8")
        built = bd.build(bd.read_oewn(path), "en", "Sample", "")
        data = gzip.decompress(built.files["en.dict.dz"])
        entries = {w: data[o : o + s].decode() for w, o, s in parse_idx(built.files["en.idx"])}
        self.assertEqual(sorted(entries), ["run", "sprint"])
        self.assertIn("move fast on foot<br><i>she runs every day</i><br>= sprint", entries["run"])
        self.assertIn("flow &lt;like water&gt;", entries["run"])
        self.assertEqual(parse_syn(built.files["en.syn"]), [("ran", 0)])

    def test_builds_are_reproducible(self):
        archives = []
        for run in ("a", "b"):
            out = self.tmp / run
            archive = bd.write(self.build_pt(), out, "pt", bd.LICENSES["wiktionary"], True)
            archives.append(archive.read_bytes())
        self.assertEqual(archives[0], archives[1])


if __name__ == "__main__":
    unittest.main()
