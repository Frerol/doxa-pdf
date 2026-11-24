# Spikes (throwaway prototypes)

Code here lives only on `spike/*` branches and is never merged into `main`. Findings are in `docs/spikes/` on `main`.

- `annot_write/`: Spike C part 1 (desktop). Writes annotations with PDFium and checks interop. `dart run bin/annot_write.dart <out>`; probes in `bin/*_probe.dart`.
- `saf_lab/`: Spike C part 2 (Android). Storage Access Framework read and write-back.
