# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate original GPL-3.0-or-later fixtures for the dictionary facade."""

import gzip
from pathlib import Path
import struct

from generate_dictzip import dictzip


def stardict_order(word):
    raw = word.encode()
    return raw.lower(), raw


def make_set(base, words, aliases=(), *, compressed=False):
    base.parent.mkdir(parents=True, exist_ok=True)
    words = sorted(words, key=stardict_order)
    index = bytearray()
    data = bytearray()
    for word in words:
        definition = f"Sample for {word}".encode()
        index += word.encode() + b"\0" + struct.pack(">II", len(data), len(definition))
        data += definition
    metadata = (
        "StarDict's dict ifo file\nversion=3.0.0\n"
        f"bookname={base.name}\nwordcount={len(words)}\n"
        f"idxfilesize={len(index)}\nsametypesequence=m\n"
    )
    if aliases:
        metadata += f"synwordcount={len(aliases)}\n"
        records = b"".join(
            alias.encode() + b"\0" + struct.pack(">I", words.index(target))
            for alias, target in sorted(aliases, key=lambda pair: stardict_order(pair[0]))
        )
        base.with_suffix(".syn").write_bytes(records)
    base.with_suffix(".ifo").write_text(metadata, encoding="utf-8")
    if compressed:
        base.with_suffix(".idx.gz").write_bytes(gzip.compress(index, mtime=0))
        base.with_suffix(".dict.dz").write_bytes(dictzip(data, 8))
    else:
        base.with_suffix(".idx").write_bytes(index)
        base.with_suffix(".dict").write_bytes(data)


def main():
    root = Path(__file__).resolve().parents[1] / "test" / "fixtures" / "lookup"
    make_set(
        root / "study",
        ["acao", "acorn", "act", "ALVO", "Alvo", "Alvo", "arco", "co-op", "zebra",
         "Álvo", "école", "Łódź", "Žaba"],
        [("Alvo", "zebra"), ("Alvo", "Alvo"), ("Alvo", "arco"), ("ALVO", "zebra"),
         ("Álvo", "act"), ("École", "co-op"), ("École", "école")],
    )
    for suffix in (".idx.gz", ".dict.dz"):
        (root / f"study{suffix}").write_bytes(b"unused malformed companion")
    make_set(root / "nested" / "accented", ["ação", "ac\u0327a\u0303o"], compressed=True)
    (root / "nested" / "invalid.ifo").write_bytes(b"\xff")


if __name__ == "__main__":
    main()
