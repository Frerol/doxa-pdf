# Ink Lab (Spike B, issue #6)

Throwaway prototype that measures S Pen input and ink latency in Flutter. It is **not product code** and is never merged
into `main`. Findings: [`docs/spikes/B-ink.md`](../../docs/spikes/B-ink.md) on `main`.

```sh
cd spikes/ink_lab
fvm flutter run --profile -d <device>    # measurements are printed as "INKLAB ..." lines (adb logcat -s flutter)
```
