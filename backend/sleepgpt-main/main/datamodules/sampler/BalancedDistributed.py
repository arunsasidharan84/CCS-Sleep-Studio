# balanced_distributed_sampler.py
from typing import Sequence, Optional, List
import math
import torch
from torch.utils.data.distributed import DistributedSampler
import torch.distributed as dist


class BalancedDistributedSampler(DistributedSampler):
    """
    A DDP-friendly balanced sampler that forms batches with 50% positives and 50% negatives
    on every replica. Works with or without replacement, supports shuffling via set_epoch().

    Args:
        dataset: torch Dataset (not used for length, kept for DistributedSampler compatibility)
        positive_indices: Sequence[int] indices for positive samples
        negative_indices: Sequence[int] indices for negative samples
        batch_size: global per-process batch size that this sampler should produce indices for
                    (i.e., the batch size used by each DDP rank's DataLoader)
        num_replicas: world size (auto-detected if None)
        rank: current rank (auto-detected if None)
        shuffle: shuffle each epoch (default: True)
        seed: base seed for shuffling (default: 0)
        drop_last: if True, drop trailing samples that don't form a full batch
        replacement: if True, sample with replacement to meet exact balanced batches even if
                     either class is short. If False, the number of batches is capped
                     by the available data from the smaller class.
    """
    def __init__(
        self,
        dataset,
        positive_indices: Sequence[int],
        negative_indices: Sequence[int],
        batch_size: int,
        num_replicas: Optional[int] = None,
        rank: Optional[int] = None,
        shuffle: bool = True,
        seed: int = 0,
        drop_last: bool = False,
        replacement: bool = True,
    ):
        # We pass shuffle=False to parent; we control shuffling ourselves via set_epoch().
        super().__init__(dataset, num_replicas=num_replicas, rank=rank, shuffle=False, seed=seed, drop_last=drop_last)

        if batch_size <= 0 or batch_size % 2 != 0:
            raise ValueError(f"`batch_size` must be a positive even number, got {batch_size}.")
        self.batch_size = batch_size
        self.half = batch_size // 2

        self.pos = torch.as_tensor(list(positive_indices), dtype=torch.long)
        self.neg = torch.as_tensor(list(negative_indices), dtype=torch.long)
        if len(self.pos) < self.half and not replacement:
            raise ValueError(f"Not enough positive samples ({len(self.pos)}) to fill even one batch half ({self.half}) without replacement.")
        if len(self.neg) < self.half and not replacement:
            raise ValueError(f"Not enough negative samples ({len(self.neg)}) to fill even one batch half ({self.half}) without replacement.")

        self.shuffle = shuffle
        self.seed = seed
        self.replacement = replacement
        self.epoch = 0  # will be set by set_epoch()

        # Precompute usable batches per replica given availability & settings
        self._recompute_plan()

    # ------------------------ helpers ------------------------

    def _rng(self) -> torch.Generator:
        g = torch.Generator()
        g.manual_seed(self.seed + self.epoch)
        return g

    def _recompute_plan(self):
        """
        Decide how many balanced batches each replica will yield this epoch,
        and thus how many indices in total we need for pos/neg globally.
        """
        world_size = self.num_replicas
        # Max batches per *replica* limited by data size when not using replacement
        if self.replacement:
            # We can make as many as floor(total_pos/half/world) but we generally
            # choose the maximum integral number given dataset sizes. To avoid huge
            # epochs when using replacement, cap by the available set lengths.
            # Here we simply base it on the larger set to allow full utilization.
            # You can also expose a max_batches_per_epoch if you want tighter control.
            # We'll align to the limiting side if replacement=False; if True, use the average of both.
            max_batches_by_pos = max(1, len(self.pos) // self.half // world_size) if len(self.pos) >= self.half else 1
            max_batches_by_neg = max(1, len(self.neg) // self.half // world_size) if len(self.neg) >= self.half else 1
            # choose at least 1
            self.num_batches_per_replica = max(1, (max_batches_by_pos + max_batches_by_neg) // 2)
        else:
            # Limited by the *smaller* class since we need equal halves without replacement
            total_pos_batches = len(self.pos) // self.half
            total_neg_batches = len(self.neg) // self.half
            total_balanced_batches = min(total_pos_batches, total_neg_batches)
            # Make it divisible by world size if drop_last, otherwise allow remainder (we'll drop anyway)
            if self.drop_last:
                total_balanced_batches = (total_balanced_batches // world_size) * world_size
            # per-replica batches:
            self.num_batches_per_replica = total_balanced_batches // world_size

        if self.drop_last:
            # Ensure each replica yields full batches only
            self.num_batches_per_replica = max(0, self.num_batches_per_replica)
        else:
            # If not dropping, ensure at least one batch if possible
            self.num_batches_per_replica = max(1, self.num_batches_per_replica)

        # Total samples per replica = batches * batch_size
        self._local_len = self.num_batches_per_replica * self.batch_size
        # For printing/debugging:
        # print(f"[rank {self.rank}] epoch={self.epoch} batches/rep={self.num_batches_per_replica}, local_len={self._local_len}")

    # ------------------------ core API ------------------------

    def __iter__(self):
        g = self._rng()

        # Shuffle order within each class per epoch (if enabled)
        pos_pool = self.pos
        neg_pool = self.neg
        if self.shuffle:
            pos_pool = pos_pool[torch.randperm(len(pos_pool), generator=g)]
            neg_pool = neg_pool[torch.randperm(len(neg_pool), generator=g)]

        # Compute how many pos/neg we need globally to serve all replicas
        world_size = self.num_replicas
        need_pos_global = self.num_batches_per_replica * self.half * world_size
        need_neg_global = self.num_batches_per_replica * self.half * world_size

        # Slice or sample with/without replacement to get exactly needed counts
        pos_indices_global = self._take_exact(pos_pool, need_pos_global, g, replacement=self.replacement)
        neg_indices_global = self._take_exact(neg_pool, need_neg_global, g, replacement=self.replacement)

        # Evenly split into replicas (equal sizes guaranteed)
        pos_chunks = pos_indices_global.split(self.num_batches_per_replica * self.half)
        neg_chunks = neg_indices_global.split(self.num_batches_per_replica * self.half)
        # Pick my share
        pos_local = pos_chunks[self.rank]
        neg_local = neg_chunks[self.rank]

        # Form per-batch 50/50 and locally shuffle inside each batch
        out: List[int] = []
        for b in range(self.num_batches_per_replica):
            p_start = b * self.half
            n_start = b * self.half
            batch = torch.cat([
                pos_local[p_start:p_start + self.half],
                neg_local[n_start:n_start + self.half]
            ], dim=0)
            # shuffle within batch for randomness
            if self.shuffle:
                perm = torch.randperm(self.batch_size, generator=g)
                batch = batch[perm]
            out.extend(batch.tolist())

        # If not drop_last and we somehow have remainder (shouldn't happen by construction),
        # you could append them here—but we keep strict balanced batches only.
        return iter(out)

    def __len__(self) -> int:
        # Number of indices this sampler will yield for *this* rank
        return self._local_len

    def set_epoch(self, epoch: int) -> None:
        self.epoch = int(epoch)
        self._recompute_plan()

    # ------------------------ utils ------------------------

    @staticmethod
    def _take_exact(pool: torch.Tensor, need: int, g: torch.Generator, replacement: bool) -> torch.Tensor:
        """
        Return exactly `need` indices from `pool`. If replacement=False, we slice the first `need`
        elements (caller should ensure `len(pool) >= need`). If replacement=True and `need` > len(pool),
        we repeat + sample the residual with replacement for exact length.
        """
        n = len(pool)
        if need <= n:
            return pool[:need].clone()

        if not replacement:
            # Should not happen if caller guarded; fallback: truncate
            return pool[:n - (n % 1)]  # keep type, essentially pool

        # With replacement: tile then draw the remainder
        times = need // n
        rem = need % n
        tiles = [pool] * times
        if rem > 0:
            # sample rem elements with replacement from pool
            idx = torch.randint(high=n, size=(rem,), generator=g)
            tiles.append(pool[idx])
        return torch.cat(tiles, dim=0)