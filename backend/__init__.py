"""Automated sleep scoring utilities."""

from pathlib import Path
import sys

_vendor = Path(__file__).resolve().parent / "vendor"
if _vendor.exists() and str(_vendor) not in sys.path:
    sys.path.append(str(_vendor))
