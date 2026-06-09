# Automated Sleep Scoring

Standalone automated 30-second sleep scoring from one or more EEG channels.

The tool now has a registry of base scorers plus an optional final SleepGPT sequence-correction step. For multi-channel EEG selection, each base scorer runs per selected EEG channel when the algorithm supports it, then averages posterior probabilities to create a consensus.

## Installed Local Assets

- `vendor/`: local Python packages installed into this folder, including `physioex`, `braindecode`, `sleepeeg`, `lunapi`, `usleep-api`, and dependencies.
- `models/pops/`: Luna POPS `s2` pretrained model resources.
- `models/usleep_braindecode/`: Braindecode U-Sleep tutorial checkpoint for offline local inference.
- `vendor/physioex/train/models/checkpoints/`: pretrained PhysioEx checkpoints for TinySleepNet, SeqSleepNet, and SleepTransformer.
- `external/`: cloned upstream source repositories for U-Time/U-Sleep, Dreamento, DeepSleepNet, TinySleepNet, and SleepTransformer.

## Algorithms

Fully local:

- `yasa`: YASA LightGBM sleep staging.
- `sleepeegpy`: SleepEEGpy-style path using MNE/YASA staging.
- `dreamento`: Dreamento-style offline autoscoring path using Dreamento's validated YASA-based approach.
- `tinysleepnet`: PhysioEx pretrained TinySleepNet.
- `seqsleepnet`: PhysioEx pretrained SeqSleepNet.
- `sleeptransformer`: PhysioEx pretrained SleepTransformer.
- `luna`: Luna POPS via `lunapi` and local `models/pops`.
- `usleep`: offline Braindecode U-Sleep architecture with a local pretrained Sleep Physionet tutorial checkpoint. The adapter accepts any single EEG channel by duplicating it into the two-channel model input, or EEG+EOG when an EOG channel is selected. If local inference fails and `USLEEP_API_TOKEN` is set, it can fall back to the official web API for EDF input.

Available but not enabled for validated inference:

- `deepsleepnet`: architecture/source/dependency code is local, but no compatible lightweight pretrained PyTorch checkpoint is distributed with the installed packages. The public pretrained DeepSleepNet archive is a large TensorFlow-era transfer-learning package, not directly compatible with this runtime. The adapter intentionally refuses to run without `AUTO_SLEEP_DEEPSLEEPNET_WEIGHTS` to avoid random-weight predictions.

## SleepGPT Correction

SleepGPT is not a base scorer. It is applied after the selected base scorer:

```bash
sleep_env/bin/python -m automated_sleep_scoring.cli recording.edf \
  --algorithm tinysleepnet \
  --sequence-correction sleepgpt \
  --eeg C3,C4 \
  --out-dir outputs
```

## Run The UI

```bash
sleep_env/bin/python automated_sleep_scoring/app.py
```

The UI lets you choose the file, output folder, base algorithm, SleepGPT correction, EEG channels, optional references, and optional EOG/EMG channels.

## CLI Examples

List channels:

```bash
sleep_env/bin/python -m automated_sleep_scoring.cli recording.edf --list-channels
```

Run YASA:

```bash
sleep_env/bin/python -m automated_sleep_scoring.cli recording.edf --algorithm yasa --out-dir outputs
```

Run PhysioEx TinySleepNet with multi-channel consensus:

```bash
sleep_env/bin/python -m automated_sleep_scoring.cli recording.edf --algorithm tinysleepnet --eeg C3,C4,F3,F4 --out-dir outputs
```

Run Luna POPS:

```bash
sleep_env/bin/python -m automated_sleep_scoring.cli recording.edf --algorithm luna --eeg C3 --ref M2 --out-dir outputs
```

Run offline U-Sleep:

```bash
sleep_env/bin/python -m automated_sleep_scoring.cli recording.edf --algorithm usleep --eeg C3 --out-dir outputs
```

Run optional U-Sleep web API fallback:

```bash
export USLEEP_API_TOKEN="your-token"
sleep_env/bin/python -m automated_sleep_scoring.cli recording.edf --algorithm usleep --eeg C3 --eog LOC-ROC --out-dir outputs
```

## Outputs

For `subject.edf`, the main output is:

- `subject_<algorithm>.json`: ScoringHero-native JSON in `[stages, annotations]` form. The stage list has one 30-second epoch record with `epoch`, `start`, `end`, `stage`, `digit`, `confidence`, `channels`, `clean`, and `source`. Automated outputs use an empty annotations list.
- `subject_<base_algorithm>_consensus_probabilities.json`: full W/N1/N2/N3/R consensus probabilities before SleepGPT correction.
- `subject_<base_algorithm>_per_channel_probabilities.json`: per-channel W/N1/N2/N3/R probabilities used to build the consensus.

The ScoringHero stage encoding is `Wake=1`, `N1=-1`, `N2=-2`, `N3=-3`, and `REM=0`. The JSON `confidence` value is the posterior probability for the assigned stage when the selected algorithm exposes probabilities; otherwise it is `null`.
