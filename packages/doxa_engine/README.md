# doxa_engine

The `PdfEngine` interface and its PDFium implementation, running in a dedicated worker isolate ([ADR-0005](../../docs/adr/0005-rendering-pipeline-and-foreign-annotations.md)). See [PDF engine §5](../../docs/plan/04-pdf-engine.md#5-engine-interface).

- `package:doxa_engine/doxa_engine.dart`: `PdfEngine`, its value types and `PdfiumEngine`.
- `package:doxa_engine/testing.dart`: `FakePdfEngine` for tests without native code.

Tests need PDFium (`tools/fetch_pdfium.sh linux`). They run one file at a time (`dart_test.yaml`), because PDFium is not thread-safe.

Part of the [Doxa PDF](../../README.md) workspace. See [architecture §2](../../docs/plan/03-architecture.md#2-repository-layout).
