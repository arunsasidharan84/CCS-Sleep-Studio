"""Configure the packaged Python runtime before importing third-party modules."""

from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path


def configure_runtime() -> None:
    backend_dir = Path(__file__).resolve().parent
    vendor_dir = backend_dir / "vendor"
    if vendor_dir.exists():
        vendor_path = str(vendor_dir)
        if vendor_path in sys.path:
            sys.path.remove(vendor_path)
        sys.path.insert(0, vendor_path)

    cache_root = Path(tempfile.gettempdir()) / "scoring_nidra_backend_cache"
    cache_root.mkdir(parents=True, exist_ok=True)
    os.environ.setdefault("NUMBA_CACHE_DIR", str(cache_root / "numba"))
    os.environ.setdefault("MPLCONFIGDIR", str(cache_root / "matplotlib"))
    os.environ.setdefault("_MNE_FAKE_HOME_DIR", str(cache_root / "mne"))
    os.environ.setdefault("OUTDATED_IGNORE", "1")

    for name in (
        "OMP_NUM_THREADS",
        "MKL_NUM_THREADS",
        "OPENBLAS_NUM_THREADS",
        "VECLIB_MAXIMUM_THREADS",
        "NUMEXPR_NUM_THREADS",
    ):
        os.environ.setdefault(name, "1")
