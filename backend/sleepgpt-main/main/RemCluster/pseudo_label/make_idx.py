import os, glob, shutil
import numpy as np
import pandas as pd
from collections import defaultdict
import pyarrow as pa
import pyarrow.ipc as ipc

# ===============================
# 你需要实现/确认的两件小事
# ===============================
def is_rem_epoch(arrow_table: pa.Table) -> bool:
    if 'stage' in arrow_table.column_names:
        val = arrow_table['stage'][0].as_py()
        return val == 4
    # 兜底：全当非REM
    return False

def load_arrow_table(path: str) -> pa.Table:
    reader = pa.ipc.RecordBatchFileReader(pa.memory_map(path, "r"))
    tbl = reader.read_all()
    return tbl

# ===============================
# 1) 扫描数据，收集 REM epoch → 构建 idx_master
# ===============================
def build_idx_master(root_dir: str, epoch_ext: str = '.arrow', epoch_zfill: int = 5):
    """
    遍历 root_dir/subject/*.arrow
    仅保留 REM 的 epoch；为每个 epoch 生成 15 条 (name,pid) 行。
    返回 pack 与一些映射。
    """
    names, pids, subjects, epochs, epoch_ids = [], [], [], [], []
    rem_epoch_key_set = set()     # 用于后面填标签的快速判断
    key2eid = {}                  # (subject, epoch_str) -> epoch_id
    eid_counter = 0

    subjects_dirs = sorted([d for d in glob.glob(os.path.join(root_dir, '*')) if os.path.isdir(d)])
    for sdir in subjects_dirs:
        subject = os.path.basename(sdir)
        for f in sorted(glob.glob(os.path.join(sdir, f'*{epoch_ext}'))):
            epoch_name = os.path.splitext(os.path.basename(f))[0]  # '00001'
            # 读取判定 REM
            tbl = load_arrow_table(f)
            if not is_rem_epoch(tbl):
                continue

            # 记录这个 REM epoch
            key = (subject, epoch_name)
            if key not in key2eid:
                key2eid[key] = eid_counter
                eid_counter += 1
            eid = key2eid[key]
            rem_epoch_key_set.add(key)

            # 为该 epoch 生成 15 条 (name,pid)
            rel = os.path.join(subject, f"{epoch_name}{epoch_ext}").replace('\\','/')
            for pid in range(15):
                names.append(rel)
                pids.append(pid)
                subjects.append(subject)
                epochs.append(epoch_name)
                epoch_ids.append(eid)

    pack = {
        'names':    np.array(names, dtype=object),
        'pids':     np.array(pids, dtype=np.int16),
        'subjects': np.array(subjects, dtype=object),
        'epochs':   np.array(epochs, dtype=object),
        'epoch_id': np.array(epoch_ids, dtype=np.int32),
    }
    rem_eids = np.unique(pack['epoch_id'])
    return pack, rem_epoch_key_set, rem_eids

# ===============================
# 2) Round-0 标签回填（仅在 REM epoch 内）
# ===============================
def build_round0_labels(idx_pack, rem_epoch_key_set,
                        patch_index_csv: str, patch_labels_npy: str,
                        epoch_zfill: int = 5, epoch_ext: str='.arrow'):
    """
    输入：
      - idx_pack：上一步产生的 master 索引（仅 REM epoch）
      - rem_epoch_key_set：REM 的 (subject, epoch) 集合
      - patch_index_csv：列含 ['subject','epoch','pid']
      - patch_labels_npy：与 CSV 行对齐的标签 ∈{1,0,-1}
    输出：
      - labels_round0：长度 = len(idx_pack['names']) 的 int8 数组，默认 -1，匹配到的行写 0/1
      - 辅助掩码：epoch_has_sup / epoch_has_pos
    """
    df = pd.read_csv(patch_index_csv)
    y  = np.load(patch_labels_npy).astype(np.int8)
    assert len(df) == len(y), "patch_index 与 patch_labels 行数不一致"
    assert {'subject','epoch','pid'}.issubset(df.columns)

    # 规范 epoch 字符串（比如补零）
    def norm_epoch_str(e):
        e = str(e)
        if e.endswith(epoch_ext):
            e = os.path.splitext(e)[0]
        return e.zfill(epoch_zfill) if e.isdigit() else e

    df = df.copy()
    df['epoch'] = df['epoch'].apply(norm_epoch_str)
    df['subject'] = df['subject'].astype(str)
    df['pid'] = df['pid'].astype(int)
    df['label'] = y

    # 仅在 REM 的 (subject, epoch) 上回填
    df = df[df.apply(lambda r: (r['subject'], r['epoch']) in rem_epoch_key_set, axis=1)]

    N = len(idx_pack['names'])
    labels = np.full((N,), fill_value=-1, dtype=np.int8)

    # 建立 (subject, epoch, pid) -> row_index 的映射，方便 O(1) 回填
    # 注意 idx_pack 里只包含 REM epoch 的行
    key2row = {}
    for i, (s, e, p) in enumerate(zip(idx_pack['subjects'], idx_pack['epochs'], idx_pack['pids'])):
        key2row[(str(s), str(e), int(p))] = i

    # 回填
    hit, miss = 0, 0
    for r in df.itertuples(index=False):
        k = (r.subject, r.epoch, int(r.pid))
        if 0 <= r.pid < 15 and k in key2row:
            if r.label in (0,1,-1):
                labels[key2row[k]] = r.label
                hit += 1
        else:
            miss += 1

    # 统计 epoch 级掩码
    epoch_ids = idx_pack['epoch_id']
    has_sup = np.bincount(epoch_ids, weights=(labels!=-1).astype(np.int32),
                          minlength=epoch_ids.max()+1) > 0
    has_pos = np.bincount(epoch_ids, weights=(labels==1).astype(np.int32),
                          minlength=epoch_ids.max()+1) > 0

    print(f"[Round0] 回填命中 {hit} 条，跳过/不在REM {miss} 条；总 N={N}")
    return labels, has_sup, has_pos

# ===============================
# 3) 保存与一个小的取索引助手
# ===============================
def save_idx_and_labels(idx_pack, labels_round0, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    np.save(os.path.join(out_dir, 'idx_master.npy'), idx_pack, allow_pickle=True)
    np.save(os.path.join(out_dir, 'round0_labels.npy'), labels_round0, allow_pickle=False)

    # 可选：epoch 级掩码
    epoch_ids = idx_pack['epoch_id']
    epoch_has_sup = np.bincount(epoch_ids, weights=(labels_round0!=-1).astype(np.int32),
                                minlength=epoch_ids.max()+1) > 0
    epoch_has_pos = np.bincount(epoch_ids, weights=(labels_round0==1).astype(np.int32),
                                minlength=epoch_ids.max()+1) > 0
    np.save(os.path.join(out_dir, 'epoch_has_sup.npy'), epoch_has_sup)
    np.save(os.path.join(out_dir, 'epoch_has_pos.npy'), epoch_has_pos)

def build_train_indices(idx_pack, labels_roundk, train_subjects):
    """
    训练期用：
      - 只在 "至少有一个标签!=-1 的 epoch" 内训练
      - BalancedSampler 的 pos/neg 行索引
      - 推断候选 infer_rows = 训练域里仍为 -1 的行
    """
    subs   = idx_pack['subjects']
    eids   = idx_pack['epoch_id']
    lab    = labels_roundk

    is_train_subj = np.isin(subs, np.array(train_subjects, dtype=object))
    epoch_has_sup = np.bincount(eids, weights=(lab!=-1).astype(np.int32),
                                minlength=eids.max()+1) > 0
    in_sup_epoch  = epoch_has_sup[eids]

    train_rows = is_train_subj & in_sup_epoch
    pos_idx = np.where(train_rows & (lab==1))[0]
    neg_idx = np.where(train_rows & (lab==0))[0]
    infer_rows = np.where(train_rows & (lab==-1))[0]

    return pos_idx, neg_idx, train_rows, infer_rows