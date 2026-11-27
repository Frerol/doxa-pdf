#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

"""Write dictionaries.json, the catalogue the app downloads packs from.

ADR-0010: the catalogue is published as an asset of the GitHub Release that
matches the app version, next to the packs built by build_dictionary.py.
The pack list and its descriptions are in tools/dictionary_packs.json; this
script reads each pack's .zip and adds what the app checks: the SHA-256 and
size of the .zip, its unpacked size, the .ifo bookname and the .ifo's
SHA-256 (which tells the app that an installed pack has a newer build).

  tools/build_dictionary_catalog.py --packs build/packs --out build/packs/dictionaries.json
  tools/build_dictionary_catalog.py --packs build/packs --check build/packs/dictionaries.json

--check fails unless the catalogue lists every pack in dictionary_packs.json
with the hashes and sizes of the files in --packs: run it on the release's
assets before publishing it.
"""

import argparse
import hashlib
import json
from pathlib import Path
import sys
import zipfile

CATALOG_FORMAT = 1
PACKS = Path(__file__).with_name("dictionary_packs.json")


class PackError(Exception):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def describe(archive: Path) -> dict:
    """What the app needs to know about one pack's .zip."""
    try:
        with zipfile.ZipFile(archive) as z:
            names = [i.filename for i in z.infolist() if not i.is_dir()]
            ifos = [n for n in names if n.endswith(".ifo")]
            if len(ifos) != 1:
                raise PackError(f"{archive.name}: expected one .ifo, found {len(ifos)}")
            base = ifos[0][: -len(".ifo")]
            for needed, variants in (("idx", (".idx", ".idx.gz")), ("dict", (".dict", ".dict.dz"))):
                if not any(base + v in names for v in variants):
                    raise PackError(f"{archive.name}: no .{needed} next to {ifos[0]}")
            ifo = z.read(ifos[0])
            unpacked = sum(i.file_size for i in z.infolist())
    except zipfile.BadZipFile as error:
        raise PackError(f"{archive.name}: {error}") from error
    book = None
    for line in ifo.decode("utf-8").splitlines():
        if line.startswith("bookname="):
            book = line[len("bookname=") :].strip()
    if not book:
        raise PackError(f"{archive.name}: the .ifo has no bookname")
    return {
        "bookName": book,
        "sha256": sha256_file(archive),
        "size": archive.stat().st_size,
        "unpackedSize": unpacked,
        "ifoSha256": hashlib.sha256(ifo).hexdigest(),
    }


def build(packs_dir: Path, packs: list[dict]) -> dict:
    entries = []
    for pack in packs:
        archive = packs_dir / pack["file"]
        if not archive.is_file():
            raise PackError(f"missing pack {archive}")
        entry = {k: v for k, v in pack.items() if k != "file"}
        # Relative, so the app resolves it against the catalogue's release.
        entry["url"] = pack["file"]
        entry.update(describe(archive))
        entries.append(entry)
    return {"format": CATALOG_FORMAT, "packs": entries}


def check(packs_dir: Path, packs: list[dict], catalog: Path) -> list[str]:
    """Differences between the catalogue and what it should say."""
    wanted = build(packs_dir, packs)
    found = json.loads(catalog.read_text(encoding="utf-8"))
    if found.get("format") != CATALOG_FORMAT:
        return [f"format is {found.get('format')!r}, not {CATALOG_FORMAT}"]
    listed = {p.get("id"): p for p in found.get("packs", [])}
    problems = []
    for pack in wanted["packs"]:
        entry = listed.pop(pack["id"], None)
        if entry is None:
            problems.append(f"{pack['id']}: not listed")
            continue
        for key, value in pack.items():
            if entry.get(key) != value:
                problems.append(f"{pack['id']}: {key} is {entry.get(key)!r}, expected {value!r}")
    problems += [f"{key}: not in {PACKS.name}" for key in listed]
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--packs", type=Path, required=True, help="folder with the packs' .zip files")
    parser.add_argument("--list", type=Path, default=PACKS, help="pack list (default: %(default)s)")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--out", type=Path, help="write the catalogue here")
    mode.add_argument("--check", type=Path, help="check this catalogue against the packs")
    args = parser.parse_args(argv)
    packs = json.loads(args.list.read_text(encoding="utf-8"))["packs"]
    try:
        if args.out:
            catalog = build(args.packs, packs)
            args.out.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            print(f"wrote {args.out} with {len(catalog['packs'])} packs")
            return 0
        problems = check(args.packs, packs, args.check)
    except PackError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    for problem in problems:
        print(f"error: {problem}", file=sys.stderr)
    if not problems:
        print(f"{args.check} matches {len(packs)} packs")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
