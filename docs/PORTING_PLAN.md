# Sleep EEG desktop port

## Architecture

- Flutter owns the desktop app shell, file picker, scoring controls, layout, and painting.
- Rust owns file loading, channel normalization, filtering, FFT/wavelet transforms, spectrograms, and display-coordinate generation.
- The initial bridge is a direct C ABI through `dart:ffi`. This can later be replaced by `flutter_rust_bridge` if generated typed APIs become more valuable than the small ABI surface.

## Folder layout

- `lib/`: Flutter desktop UI.
- `lib/src/eeg_backend.dart`: Dart FFI boundary and demo fallback.
- `rust_backend/`: Rust cdylib crate for native processing.
- `rust_backend/include/sleep_eeg.h`: C ABI contract.

## Native processing milestones

1. Port EDF loading from `ScoringHero-0.2.4/eeg/load_edf.py`.
2. Port MAT/EEGLAB loading from `ScoringHero-0.2.4/eeg/load_eeglab.py`, including v7.3 HDF5 handling.
3. Port Chebyshev filtering from `ScoringHero-0.2.4/filter/apply_filter.py`.
4. Port Welch spectrogram and periodogram code from `ScoringHero-0.2.4/signal_processing`.
5. Port Morlet time-frequency transform using `rustfft`.
6. Extend the FFI model to return channel labels, hypnogram stages, spectrogram tiles, and event annotations.

## Flutter milestones

1. Replace demo viewport with real FFI-loaded coordinates once loaders are complete.
2. Add scroll/zoom virtualization for full-night recordings.
3. Add keyboard scoring shortcuts and epoch navigation.
4. Add scoring import/export compatibility with ScoringHero formats.
5. Package native libraries into macOS and Windows app bundles.
