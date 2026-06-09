import os
import json
import numpy as np
import matplotlib.pyplot as plt
from sklearn.metrics import f1_score, accuracy_score, cohen_kappa_score
from scipy.stats import ttest_ind

# ------------------------
# 1) 度量：从混淆矩阵得到每类F1
# ------------------------
def _compute_perclass_f1_from_cm(cm: np.ndarray):
    cm = np.asarray(cm, dtype=int)
    n = cm.shape[0]
    y_true, y_pred = [], []
    for i in range(n):
        for j in range(n):
            c = int(cm[i, j])
            if c > 0:
                y_true.extend([i] * c)
                y_pred.extend([j] * c)
    if len(y_true) == 0:
        return np.full(n, np.nan)
    f1pc = f1_score(y_true, y_pred, average=None, labels=list(range(n)))
    return f1pc.astype(float)

# ------------------------
# 2) resjson 加载器
#    支持三种输入：
#    - 已是 dict
#    - 目录（包含 orig_1.json / aug_12.json）
#    - 单一 JSON 文件（整体结构 {mode:{subject:{run_key: cm}}}）
# ------------------------
def _load_resjson(resjson, subject_names, modes):
    if isinstance(resjson, dict):
        return resjson

    if isinstance(resjson, (str, os.PathLike)):
        p = str(resjson)
        if os.path.isdir(p):
            merged = {}
            for mode in modes:
                merged.setdefault(mode, {})
                for subj in subject_names:
                    fp = os.path.join(p, f"{mode}_{subj}.json")
                    if os.path.isfile(fp):
                        with open(fp, "r") as f:
                            merged[mode][subj] = json.load(f)
            return merged

        if os.path.isfile(p):
            with open(p, "r") as f:
                return json.load(f)

    raise ValueError("resjson 必须是 dict、目录路径或单一 json 文件路径。")

# ------------------------
# 3) 从 resjson 收集 per-class F1 的原始10次实验点
#    输出：f1_per_class，形状 = [len(subjects), len(modes), n_runs, n_classes]
# ------------------------
def collect_perclass_f1(resjson,
                        subject_names=('1','2','5','12'),
                        modes=('orig','aug')):
    res = _load_resjson(resjson, subject_names, modes)

    # 先探测类别数（从第一条可用的混淆矩阵）
    n_classes = None
    for mode in modes:
        md = res.get(mode, {})
        for subj in subject_names:
            sd = md.get(subj, {})
            for _, cm in sd.items():
                cm = np.asarray(cm)
                n_classes = cm.shape[0]
                break
            if n_classes is not None:
                break
        if n_classes is not None:
            break
    if n_classes is None:
        raise RuntimeError("未在 resjson 中找到任何混淆矩阵。")

    # 收集：每个 subject & mode 的每次 run 的 per-class F1
    data = {}  # (subject, mode) -> list of f1 arrays (n_classes,)
    for si, subj in enumerate(subject_names):
        for mi, mode in enumerate(modes):
            runs = []
            sd = res.get(mode, {}).get(subj, {})
            # 保持稳定顺序
            for rk in sorted(sd.keys(), key=lambda x: str(x)):
                cm = np.asarray(sd[rk], dtype=int)
                f1pc = _compute_perclass_f1_from_cm(cm)
                runs.append(f1pc)
            if len(runs) == 0:
                # 该 subject/mode 没数据，用 NaN 占位
                runs = [np.full(n_classes, np.nan)]
            data[(subj, mode)] = np.stack(runs, axis=0)  # [n_runs, n_classes]

    # 整理为统一张量：[S, M, R, C]
    # n_runs 可能不同，统一 pad 到最大
    max_runs = max(arr.shape[0] for arr in data.values())
    S, M, C = len(subject_names), len(modes), n_classes
    f1_per_class = np.full((S, M, max_runs, C), np.nan, dtype=float)

    for si, subj in enumerate(subject_names):
        for mi, mode in enumerate(modes):
            arr = data[(subj, mode)]  # [r, C]
            r = arr.shape[0]
            f1_per_class[si, mi, :r, :] = arr

    return f1_per_class  # shape [S, M, R, C]

# ------------------------
# 4) 画 per-class F1 的折线+误差条，并打印每个点的 p 值
# ------------------------
def line_plot_with_errorbars_from_resjson(resjson,
                                          subject_names=('1','2','5','12'),
                                          modes=('orig','aug'),
                                          stage_labels=('W','N1','N2','N3','REM'),
                                          save_path='MASS_Line_Plot_With_Error_Bars_PerClass.svg'):
    """
    将 X 轴设为 subject_names（如 1,2,5,12），
    Y 轴为对应 subject 的 per-class F1 在10次实验上的均值±std，
    原始 vs 增强两条线；并对每个 subject 做两组 F1 的 t 检验。
    """
    assert len(modes) == 2, "此图默认对比两个模式（如 orig vs aug）。"

    f1_per_class = collect_perclass_f1(resjson, subject_names, modes)
    # f1_per_class: [S, M=2, R, C=5]
    S, M, R, C = f1_per_class.shape
    x_labels = list(subject_names)

    fig, axes = plt.subplots(1, C, figsize=(4*C, 5), sharey=True)
    if C == 1:
        axes = [axes]

    for k, ax in enumerate(axes):  # 每个睡眠阶段一个子图
        # 两个模式的均值/方差（对 runs 取）
        mean_vals_0 = np.nanmean(f1_per_class[:, 0, :, k], axis=1)  # [S]
        std_vals_0  = np.nanstd( f1_per_class[:, 0, :, k], axis=1)

        mean_vals_1 = np.nanmean(f1_per_class[:, 1, :, k], axis=1)
        std_vals_1  = np.nanstd( f1_per_class[:, 1, :, k], axis=1)

        x = np.arange(S)
        ax.errorbar(x, mean_vals_0, yerr=std_vals_0, fmt='-o', capsize=5,
                    label=modes[0], color='blue')
        ax.errorbar(x, mean_vals_1, yerr=std_vals_1, fmt='-o', capsize=5,
                    label=modes[1], color='green')
        print(k, mean_vals_0, mean_vals_1)

        # 逐 subject 打印/标注 p 值
        for si in range(S):
            a = f1_per_class[si, 0, :, k]  # orig 的10次
            b = f1_per_class[si, 1, :, k]  # aug 的10次
            # 去掉 NaN
            a = a[~np.isnan(a)]
            b = b[~np.isnan(b)]
            if len(a) > 1 and len(b) > 1:
                stat, p = ttest_ind(a, b, equal_var=False)
                print(f"Stage {stage_labels[k]} — Subject {x_labels[si]}: p = {p:.4g}")
                # 图上简单放个文本
                ax.text(si, max(mean_vals_0[si], mean_vals_1[si]) + 0.05, f"p={p:.2g}",
                        ha='center', va='bottom', fontsize=8, rotation=0)

        ax.set_ylim(-0.05, 1.0)
        ax.set_title(stage_labels[k])
        ax.set_xlabel('Subjects')
        ax.set_xticks(x)
        ax.set_xticklabels(x_labels)
        if k == 0:
            ax.set_ylabel('F1 Score')

        ax.grid(True, linestyle='--', alpha=0.4)

    # 图例放在最右上角
    handles, labels = axes[-1].get_legend_handles_labels()
    fig.legend(handles, labels, loc='upper right')
    fig.suptitle('Per-Class F1 (mean±std over runs)')
    fig.tight_layout(rect=[0, 0.02, 1, 0.95])

    plt.savefig(save_path)
    plt.show()
    print(f"✅ 已保存图像到：{save_path}")

data_path = '/Users/hwx_admin/Sleep/temp_log/ss2_p/10_test/res.json'


line_plot_with_errorbars_from_resjson(
    resjson=data_path,
    subject_names=('1','2','5','12'),
    modes=('orig','aug')
)
