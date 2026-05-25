# Sleep EEG Desktop

Flutter + Rust desktop port of the ScoringHero sleep EEG viewer/scorer.

## What is included

- Flutter desktop app shell for macOS, Windows, and Linux.
- File picker for `.edf` and `.mat` recordings.
- Canvas-based EEG timeline painter with channel lanes and current-epoch highlight.
- Hypnogram painter and stage scoring controls.
- Dart FFI boundary in `lib/src/eeg_backend.dart`.
- Rust `cdylib` backend scaffold in `rust_backend/` with a C ABI and native memory cleanup.

The UI currently falls back to generated demo EEG coordinates when the Rust dynamic
library is not built or when EDF/MAT parsing is not yet implemented.

## Run the Flutter app

```sh
flutter pub get
flutter run -d macos
```

Use `-d windows` or `-d linux` on those platforms.

## Build the Rust backend

Rust tooling is required before this step:

```sh
cd rust_backend
cargo build --release
```

Flutter expects the native library name to be:

- macOS: `librust_sleep_eeg.dylib`
- Windows: `rust_sleep_eeg.dll`
- Linux: `librust_sleep_eeg.so`

For development, place that library where the app process can load it, or update
`EegBackend._libraryName` to use an absolute build path.

## Porting map

See `docs/PORTING_PLAN.md` for the staged migration from the Python/PyQt code in
`../ScoringHero-0.2.4`.
