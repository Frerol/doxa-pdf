# Dictionaries for Doxa PDF

Doxa looks words up **offline**, in StarDict dictionaries you add ([ADR-0009](adr/0009-offline-dictionary.md)). The app never downloads
anything itself: you download a pack here with your browser, then open it with Doxa.

## Add a dictionary in three steps

1. Download a `.zip` pack from the list below.
2. Open the downloaded file and choose **Doxa PDF** in "Open with". Doxa imports it, checks it and turns it on.
3. Back in your document, select a word and tap **Dictionary**.

You can also use **Settings → Dictionaries → Import file**. Turn dictionaries on or off there, drag them to change the order in which results
appear, or remove them.

Settings → Dictionaries also has **Import folder**, for a dictionary that is not in a `.zip`.

> **Status:** the packs below are published with `1.0.0-alpha.1` ([#43](https://github.com/Frerol/doxa-pdf/issues/43)). Until then,
> import any StarDict dictionary you have.

## Packs built by Doxa

Each pack is built from free sources with [`tools/build_dictionary.py`](../tools/build_dictionary.py). It is published with the Doxa release
it belongs to, with its SHA-256. Each `.zip` holds a `LICENSE.txt` with the source and the attribution.

| Pack | Source | Licence | Size | Download |
|---|---|---|---|---|
| English | English Wiktionary, via Wiktextract: 1,395,300 headwords | CC BY-SA 4.0 | 117.5 MB | with `1.0.0-alpha.1` |
| Português | Portuguese Wiktionary, via [Wiktextract](https://kaikki.org): 382,824 headwords | CC BY-SA 4.0 | 20.7 MB | with `1.0.0-alpha.1` |
| Português → English | English Wiktionary, via Wiktextract: 425,832 headwords | CC BY-SA 4.0 | 20.0 MB | with `1.0.0-alpha.1` |
| English → Português | English Wiktionary translations, via Wiktextract | CC BY-SA 4.0 | to be measured | with `1.0.0-alpha.1` |

In the Wiktionary packs, an inflected form leads to its dictionary form: "comia" shows its note and the entry for "comer".
A compact English pack (11.3 MB) can be built from [Open English WordNet](https://github.com/globalwordnet/english-wordnet) 2024 with the same tool.
It lists irregular forms ("ran" finds "run"), but not regular ones: "dogs" does not find "dog".

## Other dictionaries

Doxa reads any StarDict dictionary: an `.ifo` file with its `.idx` (or `.idx.gz`), `.dict` (or `.dict.dz`), and an optional `.syn`
(or `.syn.dz`). Import a `.zip`, a folder or the loose files. Check each dictionary's licence before you share it.
