#!/usr/bin/env python3
"""Command line entry point for automated sleep scoring."""

from __future__ import annotations

import os
import sys

if __package__:
    from .runtime_bootstrap import configure_runtime
else:
    from runtime_bootstrap import configure_runtime

configure_runtime()

import argparse
import json
from pathlib import Path


ALGORITHM_KEYS = (
    "dreamento",
    "gssc",
    "luna",
    "seqsleepnet",
    "sleepeegpy",
    "sleeptransformer",
    "tinysleepnet",
    "usleep",
    "yasa",
)


def parse_csv(value: str | None) -> list[str]:
    if not value:
        return []
    return [item.strip() for item in value.split(",") if item.strip()]


def log(message: str) -> None:
    print(message, flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description="Automated 30-second sleep staging from EEG.")
    parser.add_argument("data_file", nargs="?", help="Input EDF/BDF/GDF/FIF/SET file.")
    parser.add_argument("--out-dir", default=None, help="Output directory. Defaults beside the input file.")
    parser.add_argument("--algorithm", choices=ALGORITHM_KEYS, default="yasa")
    parser.add_argument("--sequence-correction", choices=["none", "sleepgpt"], default="none")
    parser.add_argument("--eeg", default=None, help="Comma-separated EEG channels. Auto-guessed if omitted.")
    parser.add_argument("--ref", default=None, help="Optional comma-separated reference channels.")
    parser.add_argument("--eog", default=None, help="Optional comma-separated EOG channels.")
    parser.add_argument("--emg", default=None, help="Optional comma-separated EMG channels.")
    parser.add_argument("--sleepgpt-alpha", type=float, default=0.1)
    parser.add_argument("--sleepgpt-ngram", type=int, default=30)
    parser.add_argument(
        "--apply-sleepgpt",
        default=None,
        help="Apply SleepGPT sequence correction to an existing ScoringNidra JSON and exit.",
    )
    parser.add_argument(
        "--output-json",
        default=None,
        help="Output path for --apply-sleepgpt. Defaults beside the input scoring file.",
    )
    parser.add_argument(
        "--export-diagnostics",
        action="store_true",
        help="Also save consensus and per-montage probability JSON files.",
    )
    parser.add_argument("--list-channels", action="store_true", help="Print detected channels and exit.")
    parser.add_argument("--check-models", action="store_true", help="Validate packaged model dependencies and exit.")
    args = parser.parse_args()

    log("PROGRESS 0.01 Initializing scientific and model dependencies")
    if __package__:
        from .scorer import scan_channels, score_file
        from .algorithms import algorithm_availability
    else:
        from scorer import scan_channels, score_file
        from algorithms import algorithm_availability
    log("PROGRESS 0.03 Model dependencies initialized")

    if args.check_models:
        availability = algorithm_availability()
        print(json.dumps(availability, indent=2), flush=True)
        # PhysioEx-based models are optional: their deep import chain
        # (physioex → pytorch_lightning → torchmetrics → torchvision) is
        # fragile inside PyInstaller bundles with unpinned CI deps.
        optional = {"tinysleepnet", "seqsleepnet", "sleeptransformer"}
        core_ok = all(
            item["available"]
            for key, item in availability.items()
            if key not in optional
        )
        if not core_ok:
            raise SystemExit(2)
        optional_failures = [
            key for key in optional
            if key in availability and not availability[key]["available"]
        ]
        if optional_failures:
            print(
                f"WARNING: Optional PhysioEx models unavailable: {optional_failures}",
                flush=True,
            )
        return
    if args.apply_sleepgpt:
        if __package__:
            from .scorer import apply_sleepgpt_to_scoring_file
        else:
            from scorer import apply_sleepgpt_to_scoring_file
        output = apply_sleepgpt_to_scoring_file(
            args.apply_sleepgpt,
            output_json=args.output_json,
            alpha=args.sleepgpt_alpha,
            ngram=args.sleepgpt_ngram,
            log=log,
        )
        print(f"Output: {output}", flush=True)
        return
    if not args.data_file:
        parser.error("data_file is required unless --check-models is used")

    channels, guesses, sfreq, duration_sec = scan_channels(args.data_file)
    if args.list_channels:
        print(f"File: {args.data_file}")
        print(f"Sample rate: {sfreq:g} Hz")
        print(f"Duration: {duration_sec / 3600:.2f} hours")
        print("\nAll channels:")
        for channel in channels:
            print(f"  {channel}")
        print("\nGuessed EEG:", ", ".join(guesses.eeg))
        print("Guessed refs:", ", ".join(guesses.ref))
        print("Guessed EOG:", ", ".join(guesses.eog))
        print("Guessed EMG:", ", ".join(guesses.emg))
        return

    eeg = parse_csv(args.eeg) if args.eeg is not None else guesses.eeg
    ref = parse_csv(args.ref) if args.ref is not None else []
    eog = parse_csv(args.eog) if args.eog is not None else guesses.eog[:2]
    emg = parse_csv(args.emg) if args.emg is not None else guesses.emg[:2]
    out_dir = Path(args.out_dir) if args.out_dir else Path(args.data_file).parent

    result = score_file(
        data_file=args.data_file,
        output_dir=out_dir,
        algorithm=args.algorithm,
        eeg_channels=eeg,
        ref_channels=ref,
        eog_channels=eog,
        emg_channels=emg,
        sequence_correction=args.sequence_correction,
        sleepgpt_alpha=args.sleepgpt_alpha,
        sleepgpt_ngram=args.sleepgpt_ngram,
        export_diagnostics=args.export_diagnostics,
        log=log,
    )
    print(f"\nAlgorithm: {result.algorithm}")
    print(f"Montages used: {', '.join(result.montages_used)}")
    print(f"Output: {result.output_json}")


if __name__ == "__main__":
    main()
