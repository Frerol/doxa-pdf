# ADR-0010 — Dictionary packs downloaded in the app on request

- **Status:** Accepted
- **Date:** 2026-11-26
- **Amends:** [ADR-0009](0009-offline-dictionary.md) (decision 2 and the "online APIs" force)

## Context
ADR-0009 made dictionaries user-imported and gave "no network access, no online APIs" as a force. The maintainer has since made the intent
clearer (2026-11-26): Doxa must **never collect data about its users**, but it is not meant to be fully offline. Cloud sync is planned, and
[NFR-SEC-001](../plan/02-requirements.md#25-security--privacy-sec) already allows network use that the user starts.

Forces:
- Today a student gets a dictionary in the browser: **Get dictionaries** opens `docs/dictionaries.md`, the browser downloads a `.zip`, and
  "Open with" brings it back to Doxa (UX §9). It works, but it leaves the app and takes several steps. Doxa will need more languages as it is translated into them.
- The packs Doxa builds from Wiktionary are large: Portuguese is 20.7 MB and English is 117.5 MB (`docs/dictionaries.md`). They cannot be bundled.
- Looking a word up must stay private. A lookup sent to a server would tell it what the student reads, word by word.
- [ADR-0007](0007-ocr-integration.md) already downloads OCR languages on request, checked by SHA-256. Dictionaries should work the same way.
- The release build has no `INTERNET` permission yet. Only the debug and profile manifests have it, for development.

## Decision
1. **Lookups stay on the device.** Doxa never sends a looked-up word, a selection or any document text to a dictionary service. Online
   dictionary APIs stay rejected. Online *translation* is a separate, opt-in feature, decided in its own ADR (#100).
2. **An in-app catalogue, fetched only when the user opens it.** Settings → Dictionaries → **Get dictionaries** (and the empty state of the
   lookup popup) shows the packs Doxa builds. Each entry gives its language, kind (definitions), size, source and licence, and says whether it is installed.
   - The catalogue is a small JSON file published as an asset of the GitHub Release that matches the app version, alongside the packs (#55).
   - Doxa fetches it only when that screen opens. There is no background refresh and no update check, and nothing is sent but a plain HTTPS
     `GET` with a generic user agent: no identifiers, no cookies, no query parameters. When there is no network, the screen says so and still offers Import file and Import folder.
3. **Downloads.**
   - Only a tap on a pack starts a download, and the size is shown first. On a metered connection, Doxa asks before starting.
   - The download shows its progress and can be cancelled. It goes to app cache and stops if free space would fall below the pack's unpacked size.
   - The file must match the SHA-256 listed in the catalogue. It then goes through the same import pipeline as ADR-0009: validate, copy into app storage, enable.
   - A failed or cancelled download leaves nothing behind.
4. **Where the code lives.** The HTTP client is `dart:io`'s `HttpClient`, so no new dependency is needed. Only the URL of the catalogue is
   fixed in the app; each pack's URL and hash come from that catalogue. The release manifest gains the `INTERNET` permission, which the OCR language downloads of ADR-0007 also need.
5. **Manual paths stay.** Import file, Import folder and "Open with" keep working for any StarDict dictionary. `docs/dictionaries.md`
   still lists the packs for people who prefer the browser.

## Consequences
- Getting a first dictionary becomes: tap **Get dictionaries**, then tap a pack. UX §9 is updated once this ADR is accepted.
- This is the first network code in the release app. Its tests run against a local test server, with no real network in CI.
- The release process (#55) must publish the catalogue with the packs, and check that every hash in the catalogue matches its file.
- Updated packs reach users only when they open the screen, which marks an installed pack that has a newer build. A pack is never replaced on its own.
- New risk: GitHub Releases availability and rate limits. If the download fails, the manual import still works.
- F-Droid: user-initiated downloads from the project's own releases are not tracking, but the store listing must say that the app can download dictionaries.

## Alternatives considered
- **Keep the browser hand-off only** (today): no network code, but more steps and the student leaves the app. It stays as a fallback.
- **Bundle a default pack:** tens to hundreds of MB in the APK, and it mixes data licences into the app (ADR-0009).
- **Online dictionary APIs:** each lookup would leave the device, against the privacy goal.
- **A Doxa server or CDN:** costs money and keeps request logs, which the project does not want to hold.
- **Automatic updates of installed packs:** network use the user did not start, and surprise downloads of 100 MB or more.
