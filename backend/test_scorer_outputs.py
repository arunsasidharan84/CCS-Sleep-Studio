from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import pandas as pd

from backend import scorer


class _DummyAlgorithm:
    def check_available(self) -> None:
        pass

    def score(self, raw, eeg, refs, eog, emg, log):
        del raw, eeg, refs, eog, emg, log
        probabilities = pd.DataFrame(
            [
                {"W": 0.8, "N1": 0.05, "N2": 0.05, "N3": 0.05, "R": 0.05},
                {"W": 0.05, "N1": 0.05, "N2": 0.8, "N3": 0.05, "R": 0.05},
            ]
        )
        per_montage = probabilities.copy()
        per_montage["epoch"] = [0, 1]
        per_montage["montage"] = "C3-M2"
        return probabilities, per_montage, ["C3-M2"]


class ScorerOutputTests(unittest.TestCase):
    def _score(self, output_dir: Path, *, export_diagnostics: bool):
        with (
            patch("backend.algorithms.available_algorithms", return_value={"yasa": _DummyAlgorithm()}),
            patch(
                "backend.scorer.prepare_raw_for_scoring",
                return_value=(object(), ["C3"], ["M2"], None, None),
            ),
            patch("backend.scorer.run_sleepgpt_correction", return_value=None),
        ):
            return scorer.score_file(
                data_file=output_dir / "night.edf",
                output_dir=output_dir,
                algorithm="yasa",
                eeg_channels=["C3"],
                ref_channels=["M2"],
                sequence_correction="sleepgpt",
                export_diagnostics=export_diagnostics,
            )

    def test_default_run_writes_only_stable_scoring_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output_dir = Path(directory)
            result = self._score(output_dir, export_diagnostics=False)

            self.assertEqual(result.output_json.name, "night_yasa_scoring.json")
            self.assertIsNone(result.probability_json)
            self.assertIsNone(result.per_channel_json)
            self.assertEqual(
                sorted(path.name for path in output_dir.iterdir()),
                ["night_yasa_scoring.json"],
            )

    def test_diagnostics_are_opt_in_and_grouped(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output_dir = Path(directory)
            result = self._score(output_dir, export_diagnostics=True)

            self.assertEqual(result.probability_json.name, "consensus_probabilities.json")
            self.assertEqual(result.per_channel_json.name, "per_montage_probabilities.json")
            self.assertEqual(result.probability_json.parent.name, "night_yasa_diagnostics")
            self.assertTrue(result.probability_json.exists())
            self.assertTrue(result.per_channel_json.exists())


if __name__ == "__main__":
    unittest.main()
