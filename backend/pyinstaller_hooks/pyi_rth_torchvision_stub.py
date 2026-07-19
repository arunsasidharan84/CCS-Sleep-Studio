"""PyInstaller runtime hook: provide a minimal torchvision stub.

torchmetrics >= 1.7 eagerly imports ``torchvision`` for its image-quality
metrics (e.g. ARNIQA).  Sleep-staging models never use image metrics, so we
inject a lightweight stub that satisfies the top-level import without pulling
in the full (and heavy) torchvision package.

This hook runs **before** application code, so by the time torchmetrics
tries ``from torchvision import transforms``, it finds the stub already
registered in ``sys.modules``.
"""

import sys
import types


class _StubModule(types.ModuleType):
    """Module whose attribute access silently returns nested stub modules."""

    def __getattr__(self, name):
        qualname = f"{self.__name__}.{name}"
        if qualname in sys.modules:
            return sys.modules[qualname]
        sub = _StubModule(qualname)
        sub.__path__ = []
        sub.__package__ = self.__name__
        sys.modules[qualname] = sub
        setattr(self, name, sub)
        return sub


if "torchvision" not in sys.modules:
    _tv = _StubModule("torchvision")
    _tv.__path__ = []
    _tv.__package__ = "torchvision"
    _tv.__version__ = "0.0.0-stub"
    sys.modules["torchvision"] = _tv
