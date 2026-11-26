#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

"""Build Doxa's free StarDict dictionary packs (issue #43, ADR-0009).

Sources, read as streams so large dumps fit in memory:

* ``wiktextract``: JSON Lines from Wiktextract (https://kaikki.org), the
  machine-readable Wiktionary. ``--lang pt`` keeps the Portuguese entries
  and their glosses (in the language of the Wiktionary edition the dump
  came from); ``--translations pt`` turns English entries into an
  English → Portuguese dictionary from their translation tables.
  Inflected forms become synonyms, so "ações" finds "ação", and an
  entry that is a form of another word (Wiktextract's ``form_of``) also
  leads to that word: "comia" shows its own note and the entry for
  "comer" (issue #92).
* ``oewn``: Open English WordNet in its WN-LMF XML release
  (https://github.com/globalwordnet/english-wordnet), for a compact
  English dictionary.

Output: ``<name>.ifo``, ``.idx``, ``.syn`` and a dictzip ``.dict.dz`` (the
format ``doxa_dict`` reads), plus ``LICENSE.txt`` with the attribution, and
with ``--zip`` a ``<name>.zip`` of them all. Builds are reproducible: the
same input gives the same bytes. Only the Python standard library is used.

Example:

    python3 tools/build_dictionary.py wiktextract pt-extract.jsonl.gz \\
        --lang pt --name doxa-pt --title "Português (Wiktionary)" \\
        --license wiktionary --out build/doxa-pt --zip
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import html
import io
import json
import struct
import sys
import xml.etree.ElementTree as ET
import zipfile
import zlib
from collections import OrderedDict
from dataclasses import dataclass, field
from pathlib import Path
from typing import IO, Iterable, Iterator

# Uncompressed bytes per dictzip chunk, as dictd's dictzip writes them.
DICTZIP_CHUNK = 58315
# The gzip extra field holds at most 65535 bytes: 10 of header, 2 per chunk.
MAX_DICTZIP_CHUNKS = (0xFFFF - 10) // 2
# StarDict 3.0.0 offsets and sizes are 32-bit without idxoffsetbits=64.
MAX_DICT_SIZE = 0xFFFFFFFF

LICENSES = {
    "wiktionary": (
        "Definitions from Wiktionary (https://www.wiktionary.org), extracted\n"
        "with Wiktextract (https://github.com/tatuylonen/wiktextract) and\n"
        "published at https://kaikki.org.\n\n"
        "Wiktionary text is available under the Creative Commons\n"
        "Attribution-ShareAlike License (CC BY-SA 4.0,\n"
        "https://creativecommons.org/licenses/by-sa/4.0/) and the GNU Free\n"
        "Documentation License. This dictionary is shared under CC BY-SA 4.0.\n"
        "Authors: the Wiktionary contributors; see each entry's history at\n"
        "https://www.wiktionary.org.\n"
    ),
    "oewn": (
        "Definitions from Open English WordNet\n"
        "(https://github.com/globalwordnet/english-wordnet), which is\n"
        "derived from Princeton WordNet 3.0.\n\n"
        "Open English WordNet is available under the Creative Commons\n"
        "Attribution 4.0 International License (CC BY 4.0,\n"
        "https://creativecommons.org/licenses/by/4.0/). Princeton WordNet is\n"
        "available under the WordNet 3.0 license\n"
        "(https://wordnet.princeton.edu/license-and-commercial-use).\n"
    ),
}


def stardict_key(word: bytes) -> tuple[bytes, bytes]:
    """StarDict's headword order: ASCII case-insensitive, then bytewise.
    (bytes.lower() folds ASCII letters only, as g_ascii_strcasecmp does.)"""
    return (word.lower(), word)


@dataclass
class Entry:
    """One headword's definition, built up from all its source records."""

    headword: str
    sections: list[str] = field(default_factory=list)
    aliases: set[str] = field(default_factory=set)


class Glossary:
    """Headwords in first-seen order, each with HTML sections and aliases."""

    def __init__(self) -> None:
        self._entries: OrderedDict[str, Entry] = OrderedDict()
        # (form, lemma) pairs from form-of senses. The lemma may come later
        # in the dump, so they are resolved in build().
        self._links: set[tuple[str, str]] = set()

    def add(self, headword: str, section: str, aliases: Iterable[str] = ()) -> None:
        headword = headword.strip()
        if not headword or "\0" in headword or not section:
            return
        entry = self._entries.setdefault(headword, Entry(headword))
        if section not in entry.sections:
            entry.sections.append(section)
        for alias in aliases:
            alias = alias.strip()
            if alias and alias != headword and "\0" not in alias:
                entry.aliases.add(alias)

    def link(self, form: str, lemma: str) -> None:
        """Makes [form] also find [lemma], when [lemma] is a headword."""
        form, lemma = form.strip(), lemma.strip()
        if form and lemma and form != lemma and "\0" not in form:
            self._links.add((form, lemma))

    def links(self) -> set[tuple[str, str]]:
        return set(self._links)

    def __len__(self) -> int:
        return len(self._entries)

    def entries(self) -> list[Entry]:
        return list(self._entries.values())


# ---------------------------------------------------------------- sources


def _open_text(path: Path) -> IO[str]:
    if path.suffix == ".gz":
        return io.TextIOWrapper(gzip.open(path, "rb"), encoding="utf-8")
    return path.open(encoding="utf-8")


def _records(path: Path) -> Iterator[dict]:
    with _open_text(path) as lines:
        for number, line in enumerate(lines, 1):
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError as error:
                raise SystemExit(f"{path}:{number}: not JSON: {error}") from None


# Forms that name a table or a template rather than a word.
_SKIPPED_FORM_TAGS = {"table-tags", "inflection-template", "class", "romanization"}


def _forms(record: dict) -> list[str]:
    forms = []
    for form in record.get("forms") or []:
        word = (form.get("form") or "").strip()
        tags = set(form.get("tags") or [])
        if word and word != "-" and not tags & _SKIPPED_FORM_TAGS:
            forms.append(word)
    return forms


def _link_lemmas(glossary: Glossary, record: dict) -> None:
    """Links a form-of entry ("comia") to the words it is a form of ("comer")."""
    word = record.get("word") or ""
    for sense in record.get("senses") or []:
        for target in sense.get("form_of") or []:
            if isinstance(target, dict):
                glossary.link(word, target.get("word") or "")


def _gloss(sense: dict) -> str | None:
    glosses = [g.strip() for g in sense.get("glosses") or [] if g and g.strip()]
    if not glosses:
        return None
    # Wiktextract lists the parent senses first; the last is this sense.
    text = html.escape(glosses[-1])
    if len(glosses) > 1:
        text = f"<i>{html.escape(glosses[0])}:</i> {text}"
    examples = [
        html.escape(e["text"].strip())
        for e in sense.get("examples") or []
        if isinstance(e, dict) and (e.get("text") or "").strip()
    ][:2]
    for example in examples:
        text += f"<br><i>{example}</i>"
    return text


def read_wiktextract(path: Path, lang: str) -> Glossary:
    """Entries of language [lang], with their glosses."""
    glossary = Glossary()
    for record in _records(path):
        if record.get("lang_code") != lang:
            continue
        _link_lemmas(glossary, record)
        word = record.get("word") or ""
        senses = [g for s in record.get("senses") or [] if (g := _gloss(s))]
        if not senses:
            continue
        items = "".join(f"<li>{s}</li>" for s in senses)
        pos = html.escape(record.get("pos") or "")
        glossary.add(word, f"<p><i>{pos}</i></p><ol>{items}</ol>", _forms(record))
    return glossary


def read_translations(path: Path, lang: str) -> Glossary:
    """English entries with their translations into [lang]."""
    glossary = Glossary()
    for record in _records(path):
        if record.get("lang_code") != "en":
            continue
        # "checking" has no translations of its own, but leads to "check".
        _link_lemmas(glossary, record)
        by_sense: OrderedDict[str, list[str]] = OrderedDict()
        for t in record.get("translations") or []:
            code = t.get("lang_code") or t.get("code")
            word = (t.get("word") or "").strip()
            if code != lang or not word:
                continue
            words = by_sense.setdefault((t.get("sense") or "").strip(), [])
            if word not in words:
                words.append(word)
        if not by_sense:
            continue
        items = "".join(
            f"<li>{f'<i>{html.escape(sense)}:</i> ' if sense else ''}"
            f"{html.escape(', '.join(words))}</li>"
            for sense, words in by_sense.items()
        )
        pos = html.escape(record.get("pos") or "")
        glossary.add(
            record.get("word") or "",
            f"<p><i>{pos}</i></p><ol>{items}</ol>",
            _forms(record),
        )
    return glossary


_OEWN_POS = {
    "n": "noun",
    "v": "verb",
    "a": "adjective",
    "s": "adjective",
    "r": "adverb",
    "c": "conjunction",
    "p": "adposition",
    "x": "other",
    "u": "unknown",
}


def read_oewn(path: Path) -> Glossary:
    """Open English WordNet (WN-LMF XML): one entry per lemma and part of
    speech, its senses numbered, with examples and synonyms."""
    synsets: dict[str, tuple[list[str], list[str]]] = {}
    lemmas: list[tuple[str, str, list[str], list[str]]] = []
    stream = gzip.open(path, "rb") if path.suffix == ".gz" else path.open("rb")
    with stream:
        for _, element in ET.iterparse(stream, events=("end",)):
            tag = element.tag
            if tag == "LexicalEntry":
                lemma = element.find("Lemma")
                if lemma is not None:
                    lemmas.append((
                        lemma.get("writtenForm") or "",
                        lemma.get("partOfSpeech") or "",
                        [s.get("synset") or "" for s in element.iter("Sense")],
                        [f.get("writtenForm") or "" for f in element.iter("Form")],
                    ))
                element.clear()
            elif tag == "Synset":
                definitions = [(d.text or "").strip() for d in element.iter("Definition")]
                examples = [(e.text or "").strip() for e in element.iter("Example")]
                synsets[element.get("id") or ""] = (
                    [d for d in definitions if d],
                    [e for e in examples if e],
                )
                element.clear()
    members: dict[str, list[str]] = {}
    for word, _, senses, _ in lemmas:
        for synset in senses:
            members.setdefault(synset, []).append(word)
    glossary = Glossary()
    for word, pos, senses, forms in lemmas:
        items = []
        for synset in senses:
            definitions, examples = synsets.get(synset, ([], []))
            if not definitions:
                continue
            text = html.escape("; ".join(definitions))
            for example in examples[:2]:
                text += f"<br><i>{html.escape(example)}</i>"
            others = [w for w in members.get(synset, []) if w != word]
            if others:
                text += "<br>= " + html.escape(", ".join(others[:8]))
            items.append(f"<li>{text}</li>")
        if items:
            section = f"<p><i>{_OEWN_POS.get(pos, pos)}</i></p><ol>{''.join(items)}</ol>"
            glossary.add(word, section, forms)
    return glossary


# ----------------------------------------------------------------- writer


def dictzip(data: bytes, name: str = "") -> bytes:
    """A dictzip stream: gzip whose DEFLATE data is flushed every
    DICTZIP_CHUNK bytes, with the chunk sizes in an "RA" extra field
    (dictd's dictzip format), so a reader can inflate any chunk alone."""
    chunks = [data[i : i + DICTZIP_CHUNK] for i in range(0, len(data), DICTZIP_CHUNK)]
    if len(chunks) > MAX_DICTZIP_CHUNKS:
        raise SystemExit("Definitions too large for one dictzip file")
    deflate = zlib.compressobj(9, zlib.DEFLATED, -15)
    body = bytearray()
    sizes = []
    for chunk in chunks:
        start = len(body)
        body += deflate.compress(chunk)
        body += deflate.flush(zlib.Z_FULL_FLUSH)
        sizes.append(len(body) - start)
    body += deflate.flush(zlib.Z_FINISH)
    if sizes:
        # The final block belongs to the last chunk.
        sizes[-1] += len(body) - sum(sizes)
    ra = struct.pack("<HHH", 1, DICTZIP_CHUNK, len(sizes))
    ra += b"".join(struct.pack("<H", s) for s in sizes)
    if any(s > 0xFFFF for s in sizes):
        raise SystemExit("A dictzip chunk did not compress to 64 KiB")
    extra = b"RA" + struct.pack("<H", len(ra)) + ra
    flags = 0x04 | (0x08 if name else 0)
    # MTIME 0 keeps builds reproducible; XFL 2 = best compression; OS 3 = Unix.
    header = b"\x1f\x8b\x08" + bytes([flags]) + b"\0\0\0\0\x02\x03"
    header += struct.pack("<H", len(extra)) + extra
    if name:
        header += name.encode("latin-1", "replace") + b"\0"
    trailer = struct.pack("<II", zlib.crc32(data), len(data) & 0xFFFFFFFF)
    return header + bytes(body) + trailer


@dataclass
class Built:
    files: dict[str, bytes]
    words: int
    synonyms: int


def build(glossary: Glossary, name: str, title: str, description: str) -> Built:
    """The StarDict files of [glossary], named [name].*."""
    entries = sorted(glossary.entries(), key=lambda e: stardict_key(e.headword.encode()))
    dict_data = bytearray()
    idx = bytearray()
    ordinals: dict[str, int] = {}
    for ordinal, entry in enumerate(entries):
        definition = "".join(entry.sections).encode()
        word = entry.headword.encode()
        idx += word + b"\0" + struct.pack(">II", len(dict_data), len(definition))
        dict_data += definition
        ordinals[entry.headword] = ordinal
    if len(dict_data) > MAX_DICT_SIZE:
        raise SystemExit("Definitions exceed 4 GiB")
    pairs = {
        (alias, ordinals[entry.headword])
        for entry in entries
        for alias in entry.aliases
        # A form that is a headword itself is found directly.
        if alias not in ordinals
    }
    # A form-of entry is a headword with only a grammatical note, so it also
    # needs a synonym that leads to its lemma's entry.
    pairs |= {
        (form, ordinals[lemma])
        for form, lemma in glossary.links()
        if lemma in ordinals
    }
    synonyms = sorted(
        pairs,
        key=lambda pair: (stardict_key(pair[0].encode()), pair[1]),
    )
    syn = b"".join(a.encode() + b"\0" + struct.pack(">I", o) for a, o in synonyms)
    info = [
        "StarDict's dict ifo file",
        "version=3.0.0",
        f"bookname={_one_line(title)}",
        f"wordcount={len(entries)}",
        f"synwordcount={len(synonyms)}",
        f"idxfilesize={len(idx)}",
        "sametypesequence=h",
        f"description={_one_line(description)}",
    ]
    files = {
        f"{name}.ifo": ("\n".join(info) + "\n").encode(),
        f"{name}.idx": bytes(idx),
        f"{name}.dict.dz": dictzip(bytes(dict_data), f"{name}.dict"),
    }
    if synonyms:
        files[f"{name}.syn"] = syn
    return Built(files, len(entries), len(synonyms))


def _one_line(text: str) -> str:
    return " ".join(text.split())


def write(built: Built, out: Path, name: str, license_text: str, zip_it: bool) -> Path | None:
    out.mkdir(parents=True, exist_ok=True)
    files = dict(built.files)
    files["LICENSE.txt"] = license_text.encode()
    for file, data in files.items():
        (out / file).write_bytes(data)
    if not zip_it:
        return None
    archive = out / f"{name}.zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_STORED) as z:
        for file in sorted(files):
            # A fixed date keeps the archive reproducible.
            info = zipfile.ZipInfo(f"{name}/{file}", date_time=(2026, 1, 1, 0, 0, 0))
            info.external_attr = 0o644 << 16
            z.writestr(info, files[file])
    return archive


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("source", choices=["wiktextract", "oewn"])
    parser.add_argument("input", type=Path, help="JSONL, LMF XML, or either .gz")
    kind = parser.add_mutually_exclusive_group()
    kind.add_argument("--lang", help="wiktextract: entries of this language code")
    kind.add_argument("--translations", help="wiktextract: English → this code")
    parser.add_argument("--name", required=True, help="file name, e.g. doxa-pt")
    parser.add_argument("--title", required=True, help="dictionary name shown in Doxa")
    parser.add_argument("--description", default="", help="one-line description")
    parser.add_argument("--license", choices=sorted(LICENSES), required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--zip", action="store_true", help="also write <name>.zip")
    args = parser.parse_args(argv)

    if args.source == "oewn":
        glossary = read_oewn(args.input)
    elif args.lang:
        glossary = read_wiktextract(args.input, args.lang)
    elif args.translations:
        glossary = read_translations(args.input, args.translations)
    else:
        parser.error("wiktextract needs --lang or --translations")
    if not len(glossary):
        print("No entries found", file=sys.stderr)
        return 1
    built = build(glossary, args.name, args.title, args.description)
    archive = write(built, args.out, args.name, LICENSES[args.license], args.zip)
    print(f"{built.words} headwords, {built.synonyms} synonyms")
    for file in sorted(built.files):
        print(f"  {file}: {len(built.files[file])} bytes")
    if archive:
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        print(f"{archive.name}: {archive.stat().st_size} bytes, sha256 {digest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
