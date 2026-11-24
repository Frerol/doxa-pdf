# Security Policy

Doxa PDF opens untrusted files, so security reports are very welcome.

## Reporting a vulnerability
**Do not open a public issue.** Use GitHub's private vulnerability reporting:
*Security* tab → *Report a vulnerability* on this repository.

Please include the affected version and platform, steps to reproduce and, if possible, a sample PDF (it stays private).
We aim to acknowledge reports within 7 days and to release fixes for critical issues as soon as possible.

## Scope
- Crashes or memory corruption triggered by crafted PDFs (including in the bundled PDFium; we coordinate with upstream).
- File-system access beyond what the user granted, unexpected network access, or execution of PDF-embedded content.

## Supported versions
Before 1.0, only the latest release receives security fixes.
