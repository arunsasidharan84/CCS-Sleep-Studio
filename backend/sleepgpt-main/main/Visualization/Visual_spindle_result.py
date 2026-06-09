import os
import sys

from scipy.stats import pearsonr
import matplotlib.pyplot as plt
import numpy as np

conf = [0] * 20
conf_og = [0] * 20
TP = 'TP'
FN = 'FN'
FP = 'FP'
# conf_og[19] = {TP: 232.0, FN: 74.0, FP: 170.0,}
# conf_og[18] = {TP: 780.0, FN: 208.0, FP: 273.0,}
# conf_og[15] = { TP: 42.0, FN: 24.0, FP: 25.0,}
# conf_og[12] = {TP: 525.0, FN: 124.0, FP: 207.0}
# conf_og[13] = { TP: 557.0, FN: 131.0, FP: 460.0}
# conf_og[11] = { TP: 438.0, FN: 137.0, FP: 324.0,}
# conf_og[6]  = {TP: 87.0, FN: 63.0, FP: 93.0}
# conf_og[5] = { TP: 141.0, FN: 52.0, FP: 80.0}
# conf_og[17] = { TP: 364.0, FN: 101.0, FP: 158.0}
# conf_og[14] = { TP: 576.0, FN: 132.0, FP: 282.0}
# conf_og[8] = {TP: 291.0, FN: 73.0, FP: 145.0,}
# conf_og[2] = { TP: 854.0, FN: 286.0, FP: 715.0}
# conf_og[10 ] = { TP: 677.0, FN: 118.0, FP: 240.0,}
# conf_og[9] = {TP: 634.0, FN: 125.0, FP: 194.0}
# conf_og[3] = { TP: 94.0, FN: 41.0, FP: 61.0}
# conf_og[1] = {TP: 604.0, FN: 108.0, FP: 230.0}
# conf_og[16] = { TP: 272.0, FN: 109.0, FP: 131.0}
# conf_og[7] = {TP: 694.0, FN: 202.0, FP: 304.0, }
# conf_og[4] = { TP: 192.0, FN: 60.0, FP: 113.0}
# #
# conf[19] = { TP: 221.0, FN: 85.0, FP: 120.0}
# conf[18] = {TP: 735.0, FN: 253.0, FP: 223.0,}
# conf[15] = { TP: 39.0, FN: 27.0, FP: 26.0}
# conf[12] = {TP: 489.0, FN: 160.0, FP: 214.0,}
# conf[13] = { TP: 573.0, FN: 115.0, FP: 456.0, }
# conf[11] = { TP: 424.0, FN: 151.0, FP: 336.0}
# conf[6] = { TP: 98.0, FN: 52.0, FP: 115.0}
# conf[5] = { TP: 127.0, FN: 66.0, FP: 63.0,}
# conf[17] = {TP: 379.0, FN: 86.0, FP: 200.0}
# conf[14] = {TP: 617.0, FN: 91.0, FP: 355.0,}
# conf[8] = {TP: 281.0, FN: 83.0, FP: 127.0}
# conf[2] = {TP: 916.0, FN: 224.0, FP: 555.0,}
# conf[10] = { TP: 644.0, FN: 151.0, FP: 192.0}
# conf[9] = {TP: 647.0, FN: 112.0, FP: 214.0}
# conf[3] = { TP: 98.0, FN: 37.0, FP: 77.0,}
# conf[1] = { TP: 605.0, FN: 107.0, FP: 199.0}
# conf[16] = {TP: 282.0, FN: 99.0, FP: 151.0,}
# conf[7] = { TP: 695.0, FN: 201.0, FP: 308.0}
# conf[4] = { TP: 171.0, FN: 81.0, FP: 90.0, }
# conf[19] = {TP: 759.0, FN: 267.0, FP: 214.0,}
# conf[18] = {TP: 1179.0, FN: 238.0, FP: 528.0,}
# conf[12] = {TP: 843.0, FN: 234.0, FP: 205.0,}
# conf[11] = {TP: 1129.0, FN: 310.0, FP: 412.0,}
# conf[6] = { TP: 602.0, FN: 234.0, FP: 380.0,}
# conf[5] = {TP: 521.0, FN: 119.0, FP: 244.0,}
# conf[17] = {TP: 982.0, FN: 204.0, FP: 269.0,}
# conf[13] = { TP: 1194.0, FN: 202.0, FP: 353.0,}
# conf[2] = {TP: 1869.0, FN: 336.0, FP: 545.0,}
# conf[14] = {TP: 1354.0, FN: 254.0, FP: 443.0,}
# conf[10] = { TP: 1537.0, FN: 400.0, FP: 154.0,}
# conf[3] = {TP: 412.0, FN: 128.0, FP: 144.0,}
# conf[9] = {TP: 1163.0, FN: 337.0, FP: 130.0, }
# conf[7] = {TP: 1245.0, FN: 331.0, FP: 217.0,}
# conf[1] = {TP: 1281.0, FN: 352.0, FP: 235.0,}
conf[19] = {TP: 875.0, FN: 151.0, FP: 349.0,}
conf[18] = {TP: 1172.0, FN: 245.0, FP: 494.0,}
conf[12] = {TP: 924.0, FN: 153.0, FP: 322.0,}
conf[11] = {TP: 1077.0, FN: 362.0, FP: 402.0,}
conf[6] = {TP: 585.0, FN: 251.0, FP: 361.0,}
conf[5] = {TP: 468.0, FN: 172.0, FP: 154.0,}
conf[17] = {TP: 978.0, FN: 208.0, FP: 286.0,}
conf[13] = { TP: 1107.0, FN: 289.0, FP: 217.0,}
conf[2] = { TP: 1915.0, FN: 290.0, FP: 550.0,}
conf[14] = {TP: 1363.0, FN: 245.0, FP: 480.0,}
conf[10] = {TP: 1632.0, FN: 305.0, FP: 243.0,}
conf[3] = {TP: 412.0, FN: 128.0, FP: 125.0,}
conf[9] = { TP: 1261.0, FN: 239.0, FP: 277.0,}
conf[7] = {TP: 1277.0, FN: 299.0, FP: 285.0,}
conf[1] = {TP: 1364.0, FN: 269.0, FP: 293.0}

# 计算每个类别的指标
def calculate_metrics(conf):
    total_tp = total_fn = total_fp = 0
    metrics_results = []

    for i, metrics in enumerate(conf):
        if metrics != 0:
            tp = metrics[TP]
            fn = metrics[FN]
            fp = metrics[FP]

            sensitivity = tp / (tp + fn) if (tp + fn) > 0 else 0
            ppv = tp / (tp + fp) if (tp + fp) > 0 else 0
            f1_score = 2 * (ppv * sensitivity) / (ppv + sensitivity) if (ppv + sensitivity) > 0 else 0
            total = tp + fn  # 总个数

            metrics_results.append((i, f1_score, sensitivity, ppv, total))

            total_tp += tp
            total_fn += fn
            total_fp += fp
        else:
            metrics_results.append((i, 0, 0, 0, 0))

    # 计算总体指标
    overall_sensitivity = total_tp / (total_tp + total_fn) if (total_tp + total_fn) > 0 else 0
    overall_ppv = total_tp / (total_tp + total_fp) if (total_tp + total_fp) > 0 else 0
    overall_f1_score = 2 * (overall_ppv * overall_sensitivity) / (overall_ppv + overall_sensitivity) if (
                                                                                                                    overall_ppv + overall_sensitivity) > 0 else 0

    metrics_results.append(('Overall', overall_f1_score, overall_sensitivity, overall_ppv, total_tp + total_fn))

    return metrics_results


metrics_results = calculate_metrics(conf)
metrics_results_orig = calculate_metrics(conf)
# for x, y in zip(metrics_results[1:-1], metrics_results_orig[1:-1]):
#     print(x[1] - y[1], x[2] - y[2], x[3] - y[3])
# print(metrics_results[-1], metrics_results_orig[-1])
valid_metrics = [(res[1], res[4]) for res in metrics_results[1:-1] if res[1] > 0 and res[4] > 0]
f1_scores, totals = zip(*valid_metrics)

# Calculate the Pearson correlation coefficient

# 提取各个指标
categories = [str(result[0]) for result in metrics_results if result[1] > 0 and result[4] > 0]
sensitivities = [result[2] for result in metrics_results[:-1] if result[1] > 0 and result[4] > 0]
ppvs = [result[3] for result in metrics_results[:-1] if result[1] > 0 and result[4] > 0]
correlation_coef, p_value = pearsonr(totals, f1_scores)

print(metrics_results)

print(f"Pearson Correlation Coefficient: {correlation_coef:.4f}")
print(f"P-Value: {p_value:.4f}")
# 绘制条形图
fig, axs = plt.subplots(3, 1, figsize=(12, 18))

# F1 Score
ax1 = axs[0]
ax2 = ax1.twinx()
ax1.bar(categories[1:], f1_scores, color='blue')
# ax1.bar(categories[1:], f1_scores[:], color='blue')

ax2.plot(categories[1:-1], [totals[i] for i in range(len(totals)-1)], color='red', marker='o')
ax1.set_ylim(0.5, 0.85)  # 设置左边y轴范围
ax2.set_ylim(50, 1500)  # 设置右边y轴范围

ax1.set_xlabel('Category')
ax1.set_ylabel('F1 Score')
ax2.set_ylabel('Total Count')
ax1.set_title('F1 Score by Category')

# Sensitivity
ax1 = axs[1]
ax2 = ax1.twinx()
ax1.bar(categories[1:], sensitivities, color='green')
ax2.plot(categories[1:-1], [totals[i] for i in range(len(totals)-1)], color='red', marker='o')
ax1.set_ylim(0.5, 0.9)  # 设置左边y轴范围
ax2.set_ylim(50, 1500)  # 设置右边y轴范围

ax1.set_xlabel('Category')
ax1.set_ylabel('Sensitivity')
ax2.set_ylabel('Total Count')
ax1.set_title('Sensitivity by Category')

# PPV
ax1 = axs[2]
ax2 = ax1.twinx()
ax1.bar(categories[1:], ppvs, color='orange')
ax2.plot(categories[1:-1], [totals[i] for i in range(len(totals)-1)], color='red', marker='o')
ax1.set_ylim(0.45, 0.8)  # 设置左边y轴范围
ax2.set_ylim(50, 1500)  # 设置右边y轴范围


ax1.set_xlabel('Category')
ax1.set_ylabel('PPV')
ax2.set_ylabel('Total Count')
ax1.set_title('PPV by Category')

plt.tight_layout()
os.makedirs('./result/spindle_results/', exist_ok=True)
plt.savefig('./result/spindle_results/expert1_aug1.svg')
plt.show()

import os
import pandas as pd
def _metrics_list_to_df(metrics_results):
    """
    metrics_results: calculate_metrics(conf) 的返回列表
      [(idx, f1, sens, ppv, total), ..., ('Overall', f1, sens, ppv, total)]
    返回 per-category DataFrame（不含 Overall）和 overall DataFrame（单行）
    """
    rows = []
    overall_row = None
    for item in metrics_results:
        if item[0] == 'Overall':
            overall_row = {
                "index": "Overall",
                "F1": float(item[1]),
                "Sensitivity": float(item[2]),
                "PPV": float(item[3]),
                "Total": int(item[4]),
            }
        else:
            idx, f1, sens, ppv, total = item
            # 只保留有效类（total>0 或 有非零指标）
            rows.append({
                "index": int(idx),
                "F1": float(f1),
                "Sensitivity": float(sens),
                "PPV": float(ppv),
                "Total": int(total),
            })
    per_cat_df = pd.DataFrame(rows).sort_values("index").reset_index(drop=True)
    overall_df = pd.DataFrame([overall_row]) if overall_row is not None else pd.DataFrame(columns=["index","F1","Sensitivity","PPV","Total"])
    return per_cat_df, overall_df

def save_spindle_results(metrics_results,
                         categories,
                         f1_scores, sensitivities, ppvs, totals,
                         outdir="./result/spindle_results",
                         filename="expert1_og1_sourcedata.xlsx",
                         aug_or_orig="aug"):
    """
    保存 calculate_metrics(conf) 的结果及画图源数据到 Excel/CSV。

    参数
    - metrics_results: calculate_metrics(conf) 的返回值
    - categories: 用于绘图的类标签（字符串列表，如 ['1','2',...])
    - f1_scores, sensitivities, ppvs: 分别对应各类的 F1、Sensitivity、PPV（与 categories 对齐）
    - totals: 各类样本总数（与 categories 对齐）
    - outdir, filename: 输出目录与文件名
    - aug_or_orig: 'aug' 或 'orig'，会体现在 sheet 名称中
    """
    os.makedirs(outdir, exist_ok=True)
    path = os.path.join(outdir, filename)
    print(len(f1_scores), len(totals), len(sensitivities), len(ppvs))
    # 1) 指标表
    per_cat_df, overall_df = _metrics_list_to_df(metrics_results)
    per_cat_df.rename(columns={"index": "Category"}, inplace=True)
    overall_df.rename(columns={"index": "Category"}, inplace=True)

    # 2) 画图数据（条形图/折线图源数据）
    plot_f1_df = pd.DataFrame({
        "Category": categories,
        "F1": np.asarray(f1_scores, dtype=float),
        "Total": np.asarray(totals, dtype=int)
    })
    plot_sens_df = pd.DataFrame({
        "Category": categories,
        "Sensitivity": np.asarray(sensitivities, dtype=float),
        "Total": np.asarray(totals, dtype=int)
    })
    plot_ppv_df = pd.DataFrame({
        "Category": categories,
        "PPV": np.asarray(ppvs, dtype=float),
        "Total": np.asarray(totals, dtype=int)
    })

    # 3) 相关性
    # Pearson(F1, Total) 已在主代码中算过；这里再算一次以确保一致
    from scipy.stats import pearsonr
    corr, pval = pearsonr(np.asarray(totals, dtype=float), np.asarray(f1_scores, dtype=float))
    corr_df = pd.DataFrame([{"pearson_r": float(corr), "p_value": float(pval)}])

    # 4) 写文件
    try:
        import openpyxl  # noqa
        with pd.ExcelWriter(path, engine="openpyxl", mode="a" if os.path.exists(path) else "w") as wr:
            per_cat_df.to_excel(wr, index=False, sheet_name=f"per_category_{aug_or_orig}")
            overall_df.to_excel(wr, index=False, sheet_name=f"overall_{aug_or_orig}")
            plot_f1_df.to_excel(wr, index=False, sheet_name=f"plot_F1_{aug_or_orig}")
            plot_sens_df.to_excel(wr, index=False, sheet_name=f"plot_Sens_{aug_or_orig}")
            plot_ppv_df.to_excel(wr, index=False, sheet_name=f"plot_PPV_{aug_or_orig}")
            corr_df.to_excel(wr, index=False, sheet_name=f"pearson_{aug_or_orig}")
        print(f"[Saved] {path} (sheets: *_{aug_or_orig})")
    except ImportError:
        # 无 openpyxl 时分别导出 CSV
        per_cat_df.to_csv(os.path.join(outdir, f"per_category_{aug_or_orig}.csv"), index=False)
        overall_df.to_csv(os.path.join(outdir, f"overall_{aug_or_orig}.csv"), index=False)
        plot_f1_df.to_csv(os.path.join(outdir, f"plot_F1_{aug_or_orig}.csv"), index=False)
        plot_sens_df.to_csv(os.path.join(outdir, f"plot_Sens_{aug_or_orig}.csv"), index=False)
        plot_ppv_df.to_csv(os.path.join(outdir, f"plot_PPV_{aug_or_orig}.csv"), index=False)
        corr_df.to_csv(os.path.join(outdir, f"pearson_{aug_or_orig}.csv"), index=False)
        print(f"[Saved CSVs] in {outdir} (prefix: *_{aug_or_orig})")
save_spindle_results(
    metrics_results=metrics_results,
    categories=categories[1],  # 你上面 bar 图用了 [1:] / [1:-1] 混合，建议统一。比如都用 [1:-1]
    f1_scores=f1_scores,          # 与 categories 对齐
    sensitivities=sensitivities,  # 与 categories 对齐
    ppvs=ppvs,                    # 与 categories 对齐
    totals=totals,           # 与 categories 对齐（你绘图里用了 len(totals)-1）
    outdir='./result/spindle_results',
    filename='expert2_aug_sourcedata.xlsx',
    aug_or_orig='aug'
)