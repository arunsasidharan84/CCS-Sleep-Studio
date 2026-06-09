# simplicial embeddings
# Lavoie et al - https://arxiv.org/abs/2204.00616

import torch
from torch import nn
from torch.nn import Module, Linear
import torch.nn.functional as F
from einops import rearrange

# helpers

def exists(v):
    return v is not None

def default(v, d):
    return v if exists(v) else d

# main class

class SEM(Module):
    def __init__(
        self,
        dim,
        num_simplices = 4,
        dim_simplex = 4,
        temperature = 0.1,
        hard = False,
        entropy_loss_weight = 0.1,
        diversity_gamma = 1.
    ):
        super().__init__()
        self.dim = dim
        self.num_simplices = num_simplices
        self.dim_simplex = dim_simplex
        self.temperature = temperature
        self.hard = hard
        self.entropy_loss_weight = entropy_loss_weight
        self.diversity_gamma = diversity_gamma

        dim_in = num_simplices * dim_simplex

        self.project_in = nn.Parameter(torch.randn(dim_in, dim))
        self.norm = nn.LayerNorm(dim_in, elementwise_affine = False)

        self.project_out = nn.Sequential(
            Linear(dim_in, dim, bias = False),
            nn.LayerNorm(dim)
        )

        bases = dim_simplex ** torch.arange(num_simplices).flip(0)
        self.register_buffer('bases', bases, persistent = False)

    @property
    def num_codes(self):
        return self.dim_simplex ** self.num_simplices

    def indices_to_one_hot(self, indices):
        indices = rearrange(indices, '... -> ... 1')
        digits = (indices // self.bases) % self.dim_simplex
        one_hot = F.one_hot(digits, self.dim_simplex).float()
        return rearrange(one_hot, '... l v -> ... (l v)')

    def one_hot_to_indices(self, one_hot):
        one_hot = rearrange(one_hot, '... (l v) -> ... l v', l = self.num_simplices, v = self.dim_simplex)
        digits = one_hot.argmax(dim = -1)
        return (digits * self.bases).sum(dim = -1)

    def forward(self, t):
        t = F.linear(t, self.project_in)
        t = self.norm(t)

        t = rearrange(t, '... (l v) -> ... l v', l = self.num_simplices, v = self.dim_simplex)

        clean_prob = (t / self.temperature).softmax(dim = -1)
        t_prob = clean_prob
        indices = t.argmax(dim = -1)

        entropy_aux_loss = torch.tensor(0., device = t.device, dtype = t.dtype)
        if self.training and self.entropy_loss_weight > 0.:
            # per_sample_entropy
            prob_clamp = clean_prob.clamp(min=1e-5)
            per_sample_entropy = (-prob_clamp * prob_clamp.log()).sum(dim=-1).mean()

            # batch_entropy
            flat_prob = rearrange(clean_prob, '... l v -> (...) l v')
            avg_prob = flat_prob.mean(dim=0).clamp(min=1e-5)
            batch_entropy = (-avg_prob * avg_prob.log()).sum(dim=-1).mean()

            entropy_aux_loss = (per_sample_entropy - self.diversity_gamma * batch_entropy) * self.entropy_loss_weight

        if self.hard:
            t_hard = F.one_hot(indices, self.dim_simplex).float()
            t_prob = t_hard + t_prob - t_prob.detach()

        # calculate discrete indices
        
        combined_indices = (indices * self.bases).sum(dim = -1)

        t_prob = rearrange(t_prob, '... l v -> ... (l v)')
        out = self.project_out(t_prob)

        return out, combined_indices, entropy_aux_loss
