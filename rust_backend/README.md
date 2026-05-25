# Rust EEG backend

This crate is the native compute layer for the Flutter desktop port.

Build commands once Rust is installed:

```sh
cd rust_backend
cargo build --release
```

Copy the produced dynamic library into a location Flutter can load while running:

- macOS: `target/release/librust_sleep_eeg.dylib`
- Windows: `target/release/rust_sleep_eeg.dll`
- Linux: `target/release/librust_sleep_eeg.so`

Current exported C ABI:

- `sleep_eeg_load_viewport(const char *path) -> SleepEegViewport *`
- `sleep_eeg_free_viewport(SleepEegViewport *viewport)`

The crate currently returns a generated demo trace and has dependency placeholders
for EDF/MAT parsing, filtering, FFT, wavelet transforms, and parallel processing.
The next implementation pass should port the logic from:

- `ScoringHero-0.2.4/eeg/load_edf.py`
- `ScoringHero-0.2.4/eeg/load_eeglab.py`
- `ScoringHero-0.2.4/filter/apply_filter.py`
- `ScoringHero-0.2.4/signal_processing/compute_morlet_tf.py`
- `ScoringHero-0.2.4/signal_processing/compute_spectogram.py`
