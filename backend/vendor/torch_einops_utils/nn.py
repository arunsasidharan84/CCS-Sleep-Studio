from __future__ import annotations
from typing import Callable

from torch.nn import Module, Sequential as PyTorchSequential
from torch_einops_utils.torch_einops_utils import exists

def Sequential(*modules):
    return PyTorchSequential(*filter(exists, modules))

class Identity(Module):
    def forward(self, t, *args, **kwargs):
        return t

class Lambda(Module):
    def __init__(self, fn: Callable):
        super().__init__()
        self.fn = fn

    def forward(self, t, *args, **kwargs):
        return self.fn(t, *args, **kwargs)
