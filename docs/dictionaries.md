# Dictionaries for Doxa PDF

Doxa looks words up **offline**, in StarDict dictionaries you add ([ADR-0009](adr/0009-offline-dictionary.md)). Words you look up never
leave your device.

## Add a dictionary

**In the app (Android):** tap **Get dictionaries** in the lookup popup or in **Settings → Dictionaries**, then tap a pack. Doxa shows its
size, downloads it from this project's GitHub Releases (asking first on mobile data), checks its SHA-256, and turns it on
([ADR-0010](adr/0010-dictionary-downloads-in-app.md)). Doxa connects to the network only when you open that list or tap a pack.

**With the browser:**
1. Download a `.zip` pack from the list below.
2. Open the downloaded file and choose **Doxa PDF** in "Open with". Doxa imports it, checks it and turns it on.
3. Back in your document, select a word and tap **Dictionary**.

You can also use **Settings → Dictionaries → Import file**, or **Import folder** for a dictionary that is not in a `.zip`. Turn dictionaries
on or off there, drag them to change the order in which results appear, or remove them.

> **Status:** the definition packs are published with `1.0.0-alpha.1` ([#43](https://github.com/Frerol/doxa-pdf/issues/43)). The
> translation packs come with the Translate action ([#100](https://github.com/Frerol/doxa-pdf/issues/100)).

## Packs built by Doxa

Each pack is built from free sources with [`tools/build_dictionary.py`](../tools/build_dictionary.py). It is published with the Doxa release
it belongs to, with its SHA-256. Each `.zip` holds a `LICENSE.txt` with the source and the attribution.

| Pack | Source | Licence | Size | Download |
|---|---|---|---|---|
| English | English Wiktionary, via Wiktextract: 1,395,300 headwords | CC BY-SA 4.0 | 117.5 MB | [`doxa-en.zip`](https://github.com/Frerol/doxa-pdf/releases/download/v1.0.0-alpha.1/doxa-en.zip) |
| Português | Portuguese Wiktionary, via [Wiktextract](https://kaikki.org): 382,824 headwords | CC BY-SA 4.0 | 20.7 MB | [`doxa-pt.zip`](https://github.com/Frerol/doxa-pdf/releases/download/v1.0.0-alpha.1/doxa-pt.zip) |
| Português → English | English Wiktionary, via Wiktextract: 425,832 headwords | CC BY-SA 4.0 | 20.0 MB | with the Translate action (#100) |
| English → Português | English Wiktionary translations, via Wiktextract | CC BY-SA 4.0 | 0.4 MB | with the Translate action (#100) |

SHA-256 of the `1.0.0-alpha.1` packs (also in the release's `dictionaries.json`, which the app checks):

| File | SHA-256 |
|---|---|
| `doxa-en.zip` | `acbf7194dbcab832743876710fa1c5d9f625a9ac9d1d265f2f9e7690714ecdfb` |
| `doxa-pt.zip` | `ae31a4d82304ae991162af8380036451a877d2d80bb70fb6d4f1df01d0983701` |

They were built on 2026-11-27 from the Wiktextract extractions downloaded from kaikki.org on 2026-11-26.

In the Wiktionary packs, an inflected form leads to its dictionary form: "comia" shows its note and the entry for "comer".
A compact English pack (11.3 MB) can be built from [Open English WordNet](https://github.com/globalwordnet/english-wordnet) 2024 with the same tool.
It lists irregular forms ("ran" finds "run"), but not regular ones: "dogs" does not find "dog".

The app's list shows the definition packs (Português and English) from
[`tools/dictionary_packs.json`](../tools/dictionary_packs.json). The translation packs belong to the separate Translate action
([#100](https://github.com/Frerol/doxa-pdf/issues/100)).

## Other dictionaries

Doxa reads any StarDict dictionary: an `.ifo` file with its `.idx` (or `.idx.gz`), `.dict` (or `.dict.dz`), and an optional `.syn`
(or `.syn.dz`). Import a `.zip`, a folder or the loose files. Check each dictionary's licence before you share it.
