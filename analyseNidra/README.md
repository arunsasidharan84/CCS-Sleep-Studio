# analyse-nidra

Native Rust port of `SleepAnalysis.py`, verified with:

- `/Users/arunsasidharan/EEGdata/Sleep/PSG/AS_CNT_08_Night1.edf`
- `/Users/arunsasidharan/EEGdata/Sleep/PSG/AS_CNT_08_Night1_yasa_sleepgpt.json`

The EDF `A1` and `A2` channels are normalized to `M1` and `M2`. By default,
`F3,F4,C3,C4,O1,O2` are analyzed after referencing to the mean of `M1,M2`.
Recordings are resampled to 250 Hz with MNE-compatible FFT resampling before
rereferencing and filtering.

## Run

```bash
~/.cargo/bin/cargo run --release -- \
  /path/to/recording.edf \
  /path/to/recording_yasa_sleepgpt.json \
  - - - - \
  /path/to/final_regional.csv
```

Choose EEG and reference channels with optional comma-separated flags:

```bash
~/.cargo/bin/cargo run --release -- \
  /path/to/recording.edf \
  /path/to/recording_yasa_sleepgpt.json \
  - - - - \
  /path/to/final_regional.csv \
  --channels F3,F4,C3,C4,O1,O2 \
  --references M1,M2
```

The flags may appear before or after the positional paths. One or more reference
channels are allowed, and their sample-wise mean is subtracted. Reference-only
channels are not included in feature, event, PAC, or regional output. `A1/A2`
may be used in the flags as aliases for `M1/M2`.

Optional positional outputs after the EDF and scoring JSON are:

1. Core stage features JSON
2. PAC JSON
3. Slow-wave JSON
4. Spindle JSON
5. Final regional CSV

Use `-` to skip an earlier output.

## Verification

Implemented and verified:

- EDF decoding, channel normalization, mastoid reference, and MNE FIR preprocessing
- Sleep architecture, Welch PSD, nonlinear features, and ACW
- IRASA decomposition and derived features
- YASA spindle detection: all 3,508 events and sample boundaries match
- YASA slow-wave detection: all 4,356 events and sample boundaries match
- Slow-wave/sigma coupling
- TensorPAC modulation index: maximum error below `2e-17`
- Regional aggregation and 253-column CSV export, including
  `sw_all_density_calc` (slow-wave count per total NREM minute)

FOOOF uses a native bounded Levenberg-Marquardt fit. Spectral band averages are
within about `0.002` on the verification recording. Some multi-peak spectra can
choose a different local optimum than SciPy's trust-region solver, so individual
center-frequency and bandwidth values are not bitwise identical.

Measured on the verification recording:

- Python spectral fixture: `194.10 s`
- Rust complete regional pipeline: `30.59 s`
- Speedup: greater than `6x`

Run the native tests with:

```bash
~/.cargo/bin/cargo test --release
```
