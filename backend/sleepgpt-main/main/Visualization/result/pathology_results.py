import glob
import os.path

import numpy as np
import matplotlib.pyplot as plt
from sklearn.metrics import roc_curve, auc
import seaborn as sns
from scipy.stats import ttest_ind
from numpy import array

import pandas as pd
# def get_all():
#     confusion_matrices = {
#         0: [[36, 2, 2],
#             [3, 19, 0],
#             [5, 3, 8]],
#         1: [[37, 2, 1],
#             [3, 19, 0],
#             [5, 3, 8]],
#         2: [[37, 1, 2],
#             [6, 16, 0],
#             [5, 2, 9]],
#         3: [[36, 1, 3],
#             [4, 18, 0],
#             [5, 2, 9]],
#         4: [[36, 2, 2],
#             [6, 16, 0],
#             [5, 2, 9]],
#         5: [[37, 1, 2],
#             [6, 16, 0],
#             [5, 3, 8]],
#         6: [[37, 1, 2],
#             [4, 18, 0],
#             [5, 3, 8]],
#         7: [[37, 2, 1],
#             [6, 16, 0],
#             [5, 2, 9]],
#         8: [[37, 2, 1],
#             [4, 18, 0],
#             [5, 3, 8]],
#         9: [[36, 1, 3],
#             [4, 18, 0],
#             [5, 2, 9]]
#     }
#     return confusion_matrices
# def get_stage_0():
#     confusion_matrices = {
#         0: [[36, 2, 2],
#             [3, 19, 0],
#             [5, 3, 8]],
#         1: [[37, 2, 1],
#             [3, 19, 0],
#             [5, 3, 8]],
#         2: [[36, 2, 2],
#             [6, 16, 0],
#             [5, 2, 9]],
#         3: [[35, 3, 2],
#             [4, 18, 0],
#             [5, 2, 9]],
#         4: [[34, 3, 3],
#             [3, 19, 0],
#             [5, 2, 9]],
#         5: [[36, 1, 3],
#             [6, 16, 0],
#             [5, 3, 8]],
#         6: [[36, 1, 3],
#             [3, 19, 0],
#             [5, 3, 8]],
#         7: [[37, 2, 1],
#             [5, 17, 0],
#             [5, 2, 9]],
#         8: [[37, 2, 1],
#             [3, 19, 0],
#             [5, 3, 8]],
#         9: [[35, 2, 3],
#             [3, 19, 0],
#             [5, 2, 9]]
#     }
#     return confusion_matrices
#
# def get_stage_1():
#     confusion_matrices = {
#         0: [[36, 2, 2],
#             [2, 20, 0],
#             [5, 3, 8]],
#         1: [[37, 2, 1],
#             [2, 20, 0],
#             [5, 3, 8]],
#         2: [[36, 2, 2],
#             [5, 17, 0],
#             [5, 2, 9]],
#         3: [[36, 2, 2],
#             [3, 19, 0],
#             [5, 2, 9]],
#         4: [[37, 1, 2],
#             [3, 19, 0],
#             [5, 2, 9]],
#         5: [[37, 2, 1],
#             [5, 17, 0],
#             [5, 3, 8]],
#         6: [[37, 1, 2],
#             [3, 19, 0],
#             [5, 3, 8]],
#         7: [[38, 1, 1],
#             [5, 17, 0],
#             [5, 2, 9]],
#         8: [[37, 2, 1],
#             [2, 20, 0],
#             [5, 3, 8]],
#         9: [[36, 1, 3],
#             [4, 18, 0],
#             [5, 2, 9]]
#
#     }
#     return confusion_matrices
#
# def get_stage_2():
#     confusion_matrices = {
#         0: [[36, 2, 2],
#             [3, 19, 0],
#             [5, 3, 8]],
#         1: [[37, 2, 1],
#             [3, 19, 0],
#             [5, 3, 8]],
#         2: [[36, 2, 2],
#             [6, 16, 0],
#             [5, 2, 9]],
#         3: [[36, 3, 1],
#             [6, 16, 0],
#             [5, 2, 9]],
#         4: [[37, 1, 2],
#             [5, 17, 0],
#             [5, 2, 9]],
#         5: [[37, 1, 2],
#             [6, 16, 0],
#             [5, 3, 8]],
#         6: [[37, 1, 2],
#             [4, 18, 0],
#             [5, 3, 8]],
#         7: [[37, 2, 1],
#             [6, 16, 0],
#             [5, 2, 9]],
#         8: [[37, 2, 1],
#             [4, 18, 0],
#             [5, 3, 8]],
#         9: [[36, 1, 3],
#             [4, 18, 0],
#             [5, 2, 9]]
#     }
#
#     return confusion_matrices
#
# def get_stage_3():
#     confusion_matrices = {
#         0: [[35, 3, 2],
#             [3, 19, 0],
#             [5, 3, 8]],
#         1: [[37, 2, 1],
#             [3, 19, 0],
#             [5, 3, 8]],
#         2: [[35, 1, 4],
#             [4, 18, 0],
#             [5, 2, 9]],
#         3: [[35, 2, 3],
#             [3, 17, 2],
#             [5, 2, 9]],
#         4: [[35, 3, 2],
#             [6, 16, 0],
#             [5, 2, 9]],
#         5: [[35, 2, 3],
#             [6, 16, 0],
#             [5, 3, 8]],
#         6: [[37, 1, 2],
#             [6, 16, 0],
#             [5, 3, 8]],
#         7: [[36, 2, 2],
#             [6, 16, 0],
#             [5, 2, 9]],
#         8: [[37, 2, 1],
#             [3, 19, 0],
#             [5, 3, 8]],
#         9: [[35, 2, 3],
#             [5, 17, 0],
#             [5, 2, 9]]
#     }
#     return confusion_matrices
#
# def get_stage_4():
#     confusion_matrices = {
#         0: [[35, 3, 2],
#             [3, 19, 0],
#             [5, 3, 8]],
#         1: [[37, 2, 1],
#             [3, 19, 0],
#             [5, 3, 8]],
#         2: [[35, 1, 4],
#             [4, 18, 0],
#             [5, 2, 9]],
#         3: [[35, 2, 3],
#             [3, 17, 2],
#             [5, 2, 9]],
#         4: [[35, 3, 2],
#             [6, 16, 0],
#             [5, 2, 9]],
#         5: [[35, 2, 3],
#             [6, 16, 0],
#             [5, 3, 8]],
#         6: [[37, 1, 2],
#             [6, 16, 0],
#             [5, 3, 8]],
#         7: [[36, 2, 2],
#             [6, 16, 0],
#             [5, 2, 9]],
#         8: [[37, 2, 1],
#             [3, 19, 0],
#             [5, 3, 8]],
#         9: [[35, 2, 3],
#             [5, 17, 0],
#             [5, 2, 9]]
#     }
#     return confusion_matrices

def get_stage_0():
    file_path = "/Users/hwx_admin/Sleep/result/UMAP/shhs1_osa/confusion_matrix_results.xlsx"
    sheet_name = "Stages_1234"
    df = pd.read_excel(file_path, sheet_name=sheet_name)

    matrices = {}
    for idx, row in df.iterrows():
        # 获取当前随机种子
        random_state = int(row["random_state"])
        # 取出所有 Cxx_Predxx 的数值
        vals = row.filter(like="C").values.astype(float)
        n = int(np.sqrt(len(vals)))  # 自动推断矩阵大小
        matrices[random_state] = np.array(vals).reshape(n, n)

    return matrices

def get_stage_1():
    file_path = "/Users/hwx_admin/Sleep/result/UMAP/shhs1_osa/confusion_matrix_results.xlsx"

    sheet_name = "Stages_0234"
    df = pd.read_excel(file_path, sheet_name=sheet_name)

    matrices = {}
    for idx, row in df.iterrows():
        # 获取当前随机种子
        random_state = int(row["random_state"])
        # 取出所有 Cxx_Predxx 的数值
        vals = row.filter(like="C").values.astype(float)
        n = int(np.sqrt(len(vals)))  # 自动推断矩阵大小
        matrices[random_state] = np.array(vals).reshape(n, n)

    return matrices

def get_stage_2():
    file_path = "/Users/hwx_admin/Sleep/result/UMAP/shhs1_osa/confusion_matrix_results.xlsx"

    sheet_name = "Stages_0134"
    df = pd.read_excel(file_path, sheet_name=sheet_name)

    matrices = {}
    for idx, row in df.iterrows():
        # 获取当前随机种子
        random_state = int(row["random_state"])
        # 取出所有 Cxx_Predxx 的数值
        vals = row.filter(like="C").values.astype(float)
        n = int(np.sqrt(len(vals)))  # 自动推断矩阵大小
        matrices[random_state] = np.array(vals).reshape(n, n)

    return matrices
def get_stage_3():
    file_path = "/Users/hwx_admin/Sleep/result/UMAP/shhs1_osa/confusion_matrix_results.xlsx"

    sheet_name = "Stages_0124"
    df = pd.read_excel(file_path, sheet_name=sheet_name)

    matrices = {}
    for idx, row in df.iterrows():
        # 获取当前随机种子
        random_state = int(row["random_state"])
        # 取出所有 Cxx_Predxx 的数值
        vals = row.filter(like="C").values.astype(float)
        n = int(np.sqrt(len(vals)))  # 自动推断矩阵大小
        matrices[random_state] = np.array(vals).reshape(n, n)

    return matrices
def get_stage_4():
    file_path = "/Users/hwx_admin/Sleep/result/UMAP/shhs1_osa/confusion_matrix_results.xlsx"

    sheet_name = "Stages_0123"
    df = pd.read_excel(file_path, sheet_name=sheet_name)

    matrices = {}
    for idx, row in df.iterrows():
        # 获取当前随机种子
        random_state = int(row["random_state"])
        # 取出所有 Cxx_Predxx 的数值
        vals = row.filter(like="C").values.astype(float)
        n = int(np.sqrt(len(vals)))  # 自动推断矩阵大小
        matrices[random_state] = np.array(vals).reshape(n, n)

    return matrices

def get_all():
    confusion_matrices = {
        0: np.array([[135, 40], [39, 136]]),
        1: np.array([[132, 43], [39, 136]]),
        2: np.array([[128, 47], [36, 139]]),
        3: np.array([[125, 50], [37, 138]]),
        4: np.array([[127, 48], [36, 139]]),
        5: np.array([[136, 39], [40, 135]]),
        6: np.array([[130, 45], [40, 135]]),
        7: np.array([[129, 46], [37, 138]]),
        8: np.array([[132, 43], [38, 137]]),
        9: np.array([[129, 46], [38, 137]]),
    }
    # 交换 class0 与 class1
    swapped = {k: v[::-1, ::-1] for k, v in confusion_matrices.items()}
    return swapped
def box_plot(metrics_by_class):
    # Adjust order to be alphabetical: Accuracy → F1 Score → Precision → Recall
    metric_colors_alphabetical = {
        "Accuracy": "lightblue",
        "F1 Score": "lightgoldenrodyellow",
        "Precision": "lightgreen",
        "Recall": "lightcoral"
    }
    metric_order_alphabetical = sorted(metric_colors_alphabetical.keys())

    # Prepare data for combined boxplot with alphabetical order of metrics
    combined_data_alphabetical = []
    combined_labels_alphabetical = []
    positions_alphabetical = []
    position_counter_alphabetical = 0

    # Add spacing between different classes with new metric order
    for class_idx, (class_name, metrics) in enumerate(metrics_by_class.items()):
        combined_data_alphabetical.extend([metrics[metric] for metric in metric_order_alphabetical])
        combined_labels_alphabetical.extend([
            f"{class_name}\n{metric}" for metric in metric_order_alphabetical
        ])
        positions_alphabetical.extend(
            [position_counter_alphabetical + i for i in range(len(metric_order_alphabetical))])
        position_counter_alphabetical += len(metric_order_alphabetical) + 1

    # Plot combined boxplot with alphabetical metric order
    plt.figure(figsize=(18, 8))
    bplots_alphabetical = plt.boxplot(
        combined_data_alphabetical,
        patch_artist=True,          # Enable box fill colors
        showmeans=False,            # Remove mean marker (triangle)
        showfliers=False,           # Optional: Remove outlier markers
        medianprops={'color': 'black', 'linewidth': 2},  # Median line in black
        positions=positions_alphabetical
    )

    # Apply metric-specific colors
    for patch, label in zip(bplots_alphabetical['boxes'], combined_labels_alphabetical):
        for metric, color in metric_colors_alphabetical.items():
            if metric in label:
                patch.set_facecolor(color)

    # Adjust labels and spacing
    plt.xticks(positions_alphabetical, combined_labels_alphabetical, rotation=45)
    plt.title("Metrics Distribution Across All Classes (Alphabetical Order: Accuracy, F1 Score, Precision, Recall)")
    plt.ylabel("Metric Values")
    plt.xlabel("Classes and Metrics")
    plt.grid(axis="y", linestyle="--", alpha=0.7)
    plt.tight_layout()
    plt.savefig('/Users/hwx_admin/Sleep/result/UMAP/classification/box_plot.svg')
    plt.show()
def box_plot_2(metrics_by_class):
    # Define metrics and Pathology categories
    metrics = ["Accuracy", "F1 Score", "Precision", "Recall", ]
    pathology_colors = {
        "Pathology 0": "lightblue",
        "Pathology 1": "lightgreen",
        "Pathology 2": "lightcoral"
    }

    # Prepare data for boxplot
    combined_data = []
    combined_labels = []
    positions = []
    position_counter = 0

    # Iterate over metrics
    for metric in metrics:
        for pathology_idx, (pathology_name, pathology_metrics) in enumerate(metrics_by_class.items()):
            # Add metric data for this pathology
            combined_data.append(pathology_metrics[metric])
            combined_labels.append(f"{metric}\n{pathology_name}")
            positions.append(position_counter)
            position_counter += 1
        # Add spacing between different metrics
        position_counter += 1

    # 修正 metric_positions 的计算逻辑
    num_pathologies = len(pathology_colors)
    metric_positions = [
        np.mean(positions[i:i + num_pathologies]) for i in range(0, len(positions), num_pathologies + 1)
    ]

    # 修正 xticks 数量
    if len(metric_positions) != len(metrics):
        metric_positions = [
            np.mean(positions[i:i + num_pathologies]) for i in range(0, len(positions), num_pathologies)
        ]

    # Plot the boxplot
    plt.figure(figsize=(18, 8))
    bplots = plt.boxplot(
        combined_data,
        patch_artist=True,          # Enable box fill colors
        showmeans=False,            # Remove mean marker
        showfliers=False,           # Optional: Remove outlier markers
        medianprops={'color': 'black', 'linewidth': 2},  # Median line in black
        positions=positions
    )

    # Apply colors based on Pathology
    for patch, label in zip(bplots['boxes'], combined_labels):
        for pathology_name, color in pathology_colors.items():
            if pathology_name in label:
                patch.set_facecolor(color)

    # Adjust labels and spacing
    plt.xticks(metric_positions, metrics, fontsize=12)  # 修正后确保 metric_positions 与 metrics 对齐
    plt.title("Metrics Distribution for Different Pathologies", fontsize=16)
    plt.ylabel("Metric Values", fontsize=14)
    plt.xlabel("Metrics", fontsize=14)
    plt.grid(axis="y", linestyle="--", alpha=0.7)
    plt.tight_layout()
    plt.savefig('/Users/hwx_admin/Sleep/result/UMAP/classification/box_plot_pathology_metrics.svg')
    plt.show()

def calculate_classwise_metrics(cm):
    total = np.sum(cm)  # Total number of samples
    accuracy = np.trace(cm) / total  # Accuracy

    class_metrics = {}
    cm = np.array(cm)
    f1_scores = []  # 用于汇总 F1 分数
    # Calculate metrics for each class
    for i in range(len(cm)):
        TP = cm[i, i]
        FP = np.sum(cm[:, i]) - TP  # False positives for class i
        FN = np.sum(cm[i, :]) - TP  # False negatives for class i
        TN = total - (TP + FP + FN)  # True negatives for class i

        # Precision, Recall, and F1 for class i
        precision = TP / (TP + FP) if (TP + FP) > 0 else 0
        recall = TP / (TP + FN) if (TP + FN) > 0 else 0
        f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0
        # Sensitivity (Recall for class i)
        f1_scores.append(f1)  # 保存每个类别的 F1 Score
        sensitivity = TP / (TP + FN) if (TP + FN) > 0 else 0

        # Specificity (True Negative Rate for class i)
        specificity = TN / (TN + FP) if (TN + FP) > 0 else 0

        # Class-wise accuracy calculation
        total_for_class = TP + FP + FN + TN
        class_accuracy = (TP + TN) / total_for_class if total_for_class > 0 else 0

        class_metrics[f'Class {i}'] = {
            'Accuracy': class_accuracy,
            'Precision': precision,
            'Recall': recall,
            'Sensitivity': sensitivity,
            'Specificity': specificity,
            'F1 Score': f1
        }
    macro_f1 = np.mean(f1_scores) if f1_scores else 0
    return accuracy, macro_f1, class_metrics
import numpy as np
import matplotlib.pyplot as plt
from sklearn.metrics import roc_curve, auc
import pandas as pd
import torch

def get_roc_auc(data):
    all_preds, all_trues = [], []
    for repetition in data:
        preds = np.array(repetition['pred'])
        trues = np.array(repetition['true'])
        all_preds.append(preds)
        all_trues.append(trues)

    num_classes = 3
    all_fpr = np.linspace(0, 1, 100)
    tprs = [[] for _ in range(num_classes)]
    aucs = [[] for _ in range(num_classes)]

    for i in range(len(all_preds)):
        preds = all_preds[i]
        trues = all_trues[i]
        preds = np.array(torch.softmax(torch.from_numpy(preds), dim=-1))
        for cls in range(num_classes):
            binary_true = (trues == cls).astype(int)
            binary_pred = preds[:, cls]
            fpr, tpr, _ = roc_curve(binary_true, binary_pred)
            tprs[cls].append(np.interp(all_fpr, fpr, tpr))
            aucs[cls].append(auc(fpr, tpr))

    mean_tprs = [np.mean(cls_tprs, axis=0) for cls_tprs in tprs]
    std_tprs = [np.std(cls_tprs, axis=0) for cls_tprs in tprs]
    mean_aucs = [np.mean(cls_aucs) for cls_aucs in aucs]
    std_aucs = [np.std(cls_aucs) for cls_aucs in aucs]

    # ============ 保存到 Excel ============
    writer = pd.ExcelWriter('/Users/hwx_admin/Sleep/result/UMAP/classification/roc_results.xlsx', engine='openpyxl')
    for cls in range(num_classes):
        df = pd.DataFrame({
            'FPR': all_fpr,
            'TPR_mean': mean_tprs[cls],
            'TPR_std': std_tprs[cls],
        })
        df.to_excel(writer, sheet_name=f'Class_{cls}', index=False)
    # 写入AUC汇总
    summary_df = pd.DataFrame({
        'Class': [f'Class_{i}' for i in range(num_classes)],
        'Mean_AUC': mean_aucs,
        'Std_AUC': std_aucs
    })
    summary_df.to_excel(writer, sheet_name='AUC_Summary', index=False)
    writer.close()
    print("✅ ROC data saved to Excel: roc_results.xlsx")

    # ============ 绘图 ============
    plt.figure(figsize=(10, 8))
    colors = ['b', 'g', 'r']
    for cls in range(num_classes):
        plt.plot(all_fpr, mean_tprs[cls], color=colors[cls],
                 label=f'Class {cls} (AUC = {mean_aucs[cls]:.3f} ± {std_aucs[cls]:.3f})')
        plt.fill_between(all_fpr, mean_tprs[cls] - std_tprs[cls], mean_tprs[cls] + std_tprs[cls],
                         color=colors[cls], alpha=0.2)

    plt.plot([0, 1], [0, 1], linestyle='--', color='gray', label='Random')
    plt.xlabel('1 - Specificity (False Positive Rate)')
    plt.ylabel('Sensitivity (True Positive Rate)')
    plt.title('Average ROC Curves with AUC ± Std')
    plt.legend()
    plt.savefig('/Users/hwx_admin/Sleep/result/UMAP/classification/auc.svg')
    plt.show()


def plot_normalized_confusion_matrix(cm_list, class_labels, title="Normalized Confusion Matrix"):

    overall_cm = np.zeros_like(next(iter(cm_list)), dtype=np.float64)  # 初始化矩阵
    for cm in cm_list:
        overall_cm += np.array(cm)  # 累加每个混淆矩阵

    # 归一化混淆矩阵（按行进行归一化）
    cm_normalized = overall_cm.astype('float') / overall_cm.sum(axis=1)[:, np.newaxis]

    # 绘制热图
    plt.figure(figsize=(8, 6))
    sns.set(font_scale=1.2)
    sns.heatmap(
        cm_normalized, annot=True, fmt=".3f", cmap="Blues",
        xticklabels=class_labels, yticklabels=class_labels,
        cbar_kws={'label': 'Proportion'}, linewidths=1, linecolor='white'
    )

    # 设置标题和坐标轴标签
    plt.title(title, fontsize=16, weight='bold')
    plt.ylabel("Ground Truth labels", fontsize=12)
    plt.xlabel("Predicted labels", fontsize=12)
    plt.savefig('/Users/hwx_admin/Sleep/result/UMAP/classification/cm.svg')
    plt.show()


def plot_f1_scores_vs_baseline(stage_functions, stage_names, baseline_func):
    # 1. 计算 baseline 的 F1 Scores
    baseline_cm_list = baseline_func().values()
    metric_name = 'F1 Score' ##'F1 Score'

    _, _, baseline_metrics = zip(*[calculate_classwise_metrics(cm) for cm in baseline_cm_list])
    baseline_f1 = {f"Class {i}": [metrics[f"Class {i}"][metric_name] for metrics in baseline_metrics] for i in range(2)}

    # 2. 计算每个 Stage 的 F1 Scores
    stage_f1_scores = []
    for stage_func, stage_name in zip(stage_functions, stage_names):
        cm_list = stage_func().values()
        _, _, class_metrics = zip(*[calculate_classwise_metrics(cm) for cm in cm_list])
        for class_idx in range(2):  # 三个 Class
            for metrics in class_metrics:
                stage_f1_scores.append({
                    "Stage": stage_name,
                    "Class": f"Class {class_idx}",
                    metric_name: metrics[f"Class {class_idx}"][metric_name]
                })
    # 将 baseline 数据添加到 stage 数据中
    for class_idx in range(2):
        for f1_value in baseline_f1[f"Class {class_idx}"]:
            stage_f1_scores.append({
                "Stage": "Baseline",  # 标记为 Baseline
                "Class": f"Class {class_idx}",
                metric_name: f1_value
            })

    stage_f1_df = pd.DataFrame(stage_f1_scores)
    # 将 Stage 转换为有序类别，并重新排序 DataFrame
    stage_order = ["Baseline"] + stage_names
    stage_f1_df["Stage"] = pd.Categorical(stage_f1_df["Stage"], categories=stage_order, ordered=True)
    stage_f1_df["Class"] = pd.Categorical(stage_f1_df["Class"], categories=[f"Class {i}" for i in range(3)],
                                          ordered=True)

    # 根据 Stage 和 Class 排序
    stage_f1_df = stage_f1_df.sort_values(["Stage", "Class"]).reset_index(drop=True)
    print(stage_f1_df)
    plt.figure(figsize=(15, 6))

    # 3. 绘制每个 Class 的 F1 分数
    for class_idx in range(2):  # 分别绘制 Class 0, 1, 2
        plt.subplot(1, 3, class_idx + 1)
        class_name = f"Class {class_idx}"
        class_data = stage_f1_df[stage_f1_df["Class"] == class_name]

        # 绘制 Baseline 和各个 Stage 的 F1 Scores
        sns.stripplot(x="Stage", y=metric_name, data=class_data, jitter=True, alpha=0.7, size=2, order=stage_order)
        # sns.boxplot(x="Stage", y=metric_name, data=class_data, showfliers=False, color="white", width=0.4, order=stage_order)

        # 计算显著性
        baseline_f1_values = baseline_f1[class_name]
        p_values = []
        for stage_name in stage_names:
            stage_f1_values = class_data[class_data["Stage"] == stage_name][metric_name]
            stat, p = ttest_ind(stage_f1_values, baseline_f1_values)
            p_values.append((stage_name, p))

        # 添加显著性标注
        max_y = class_data[metric_name].max()
        baseline_x = 0  # Baseline的 x 坐标
        for i, (stage_name, p) in enumerate(p_values):
            if p < 0.05:
                stage_x = stage_order.index(stage_name)
                y = max_y + 0.02 * (i + 1)
                plt.plot([baseline_x, stage_x], [y, y], lw=1.5, color="black")  # Baseline vs Stage
                plt.text((baseline_x + stage_x) / 2, y + 0.005, f"p = {p:.1e}", ha="center", va="bottom", fontsize=8)

        plt.title(class_name)
        plt.ylabel(metric_name)
        plt.xlabel("Stages")
        plt.ylim(0, 1)
        plt.grid(axis="y", linestyle="--", alpha=0.7)

    plt.tight_layout()
    plt.savefig('/Users/hwx_admin/Sleep/result/UMAP/classification/f1_vs_baseline_ordered.svg')
    plt.show()


def plot_f1_scores_vs_baseline_bar(stage_functions, stage_names, baseline_func,
                                   save_dir='/Users/hwx_admin/Sleep/result/UMAP/classification',
                                   save_xlsx='f1_apnea_bar_scatter_source.xlsx',
                                   save_fig='f1_apnea_bar_scatter.svg', range_len=3):
    """
    画柱状图（mean±std）并叠加每个样本的 F1 散点；同时保存
      1) source data（逐样本 F1，tidy/long）
      2) per-class 分组统计（mean/std/count）
      3) p-values：Baseline vs 各 Stage（Welch t-test）
      4) p-values：Stage 1 vs 其它 Stage（如存在 Stage 1）
    """
    os.makedirs(save_dir, exist_ok=True)
    xlsx_path = os.path.join(save_dir, save_xlsx)
    fig_path  = os.path.join(save_dir, save_fig)

    # 1) baseline 的 F1
    baseline_cm_list = baseline_func().values()
    metric_name = 'F1 Score'
    _, _, baseline_metrics = zip(*[calculate_classwise_metrics(cm) for cm in baseline_cm_list])
    baseline_f1 = {f"Class {i}": [m[f"Class {i}"][metric_name] for m in baseline_metrics] for i in range(range_len)}

    # 2) 各 Stage 的 F1（长表）
    rows_long = []
    for stage_func, stage_name in zip(stage_functions, stage_names):
        cm_list = stage_func().values()
        _, _, cls_metrics_list = zip(*[calculate_classwise_metrics(cm) for cm in cm_list])
        for class_idx in range(range_len):
            for ms in cls_metrics_list:
                rows_long.append({
                    "Class": f"Class {class_idx}",
                    "Stage": stage_name,
                    "F1": ms[f"Class {class_idx}"][metric_name]
                })
    # 追加 Baseline
    for class_idx in range(range_len):
        for f1v in baseline_f1[f"Class {class_idx}"]:
            rows_long.append({
                "Class": f"Class {class_idx}",
                "Stage": "Baseline",
                "F1": f1v
            })

    df_long = pd.DataFrame(rows_long)
    stage_order = ["Baseline"] + stage_names
    df_long["Stage"] = pd.Categorical(df_long["Stage"], categories=stage_order, ordered=True)

    # 3) 分组统计
    group_stats = (
        df_long
        .groupby(["Class", "Stage"])["F1"]
        .agg(["mean", "std", "count"])
        .reset_index()
        .sort_values(["Class", "Stage"])
    )

    def _to_wide(g):
        w = g.pivot(index="Class", columns="Stage", values="mean").add_suffix("_mean")
        s = g.pivot(index="Class", columns="Stage", values="std").add_suffix("_std")
        c = g.pivot(index="Class", columns="Stage", values="count").add_suffix("_n")
        return pd.concat([w, s, c], axis=1).reset_index()

    group_stats_wide = _to_wide(group_stats)

    # 4) p-values
    pval_rows_base, pval_rows_s1 = [], []
    for cls in [f"Class {i}" for i in range(range_len)]:
        base_vals = df_long[(df_long["Class"] == cls) & (df_long["Stage"] == "Baseline")]["F1"].values
        for st in stage_names:
            st_vals = df_long[(df_long["Class"] == cls) & (df_long["Stage"] == st)]["F1"].values
            if len(base_vals) > 1 and len(st_vals) > 1:
                stat, p = ttest_ind(st_vals, base_vals, equal_var=False)
            else:
                stat, p = np.nan, np.nan
            pval_rows_base.append({"Class": cls, "Stage_vs": st, "t_stat": stat, "p_value": p})

        if "Stage 1" in stage_names:
            s1_vals = df_long[(df_long["Class"] == cls) & (df_long["Stage"] == "Stage 1")]["F1"].values
            for st in stage_names:
                st_vals = df_long[(df_long["Class"] == cls) & (df_long["Stage"] == st)]["F1"].values
                if len(s1_vals) > 1 and len(st_vals) > 1:
                    stat, p = ttest_ind(st_vals, s1_vals, equal_var=False)
                else:
                    stat, p = np.nan, np.nan
                pval_rows_s1.append({"Class": cls, "Stage1_vs": st, "t_stat": stat, "p_value": p})

    pvals_baseline_df = pd.DataFrame(pval_rows_base)
    pvals_stage1_df   = pd.DataFrame(pval_rows_s1)

    # 5) 画图（柱状 + 逐点散点）
    plt.figure(figsize=(6*range_len, 6))
    for class_idx in range(range_len):
        plt.subplot(1, range_len, class_idx + 1)
        cls_name = f"Class {class_idx}"
        sub = df_long[df_long["Class"] == cls_name]
        stats = sub.groupby("Stage")["F1"].agg(["mean", "std"]).reindex(stage_order)

        x = np.arange(len(stage_order))
        bar_width = 0.9
        plt.bar(x, stats["mean"], yerr=stats["std"], capsize=4,
                color="lightblue", edgecolor="black", width=bar_width, zorder=1)

        # ——叠加逐样本散点——
        jitter_width = bar_width * 0.35  # 抖动范围
        dot_size = 18
        for i, st in enumerate(stage_order):
            y_vals = sub[sub["Stage"] == st]["F1"].values
            if len(y_vals) == 0:
                continue
            # 让散点在条形内部左右随机分布
            x_jitter = x[i] + (np.random.rand(len(y_vals)) - 0.5) * 2 * jitter_width
            plt.scatter(x_jitter, y_vals, s=dot_size, c="k", alpha=0.6, zorder=2)

        # 标注显著性（Baseline 对比）
        base_row = pvals_baseline_df[pvals_baseline_df["Class"] == cls_name]
        max_y = max(sub["F1"].max(), (stats["mean"] + stats["std"]).max()) + 0.02
        for i, st in enumerate(stage_names):
            p_series = base_row.loc[base_row["Stage_vs"] == st, "p_value"]
            p = float(p_series.iloc[0]) if not p_series.empty else np.nan
            if not np.isnan(p) and p < 0.05:
                plt.text(i+1, max_y + i*0.02, f"p={p:.3g}", ha="center", fontsize=9)

        plt.title(cls_name)
        plt.ylabel("F1 Score")
        plt.xlabel("Stages")
        plt.xticks(x, stage_order, rotation=0)
        plt.ylim(0, 1.1)
        plt.grid(axis="y", linestyle="--", alpha=0.4, zorder=0)

    plt.tight_layout()
    plt.savefig(fig_path, dpi=300, bbox_inches="tight")
    plt.show()


    # 6) 保存到 Excel
    with pd.ExcelWriter(xlsx_path, engine="openpyxl") as writer:
        # 逐样本 source data（画图用到的所有点）
        df_long.sort_values(["Class", "Stage"]).to_excel(writer, sheet_name="source_long", index=False)
        # 分组统计 mean/std（长表）
        group_stats.to_excel(writer, sheet_name="group_stats_long", index=False)
        # 分组统计 mean/std（宽表，更直观）
        group_stats_wide.to_excel(writer, sheet_name="group_stats_wide", index=False)
        # p-values（Baseline vs 各 Stage）
        pvals_baseline_df.to_excel(writer, sheet_name="pvalues_vs_baseline", index=False)
        # p-values（Stage1 vs 其它 Stage）
        pvals_stage1_df.to_excel(writer, sheet_name="pvalues_vs_stage1", index=False)

    print(f"✅ 图已保存：{fig_path}")
    print(f"✅ source data 与 p-values 已保存：{xlsx_path}")


def plot_macro_f1_vs_baseline(stage_functions, stage_names, baseline_func):
    # 1. 计算 Baseline 的 Macro-F1
    baseline_cm_list = baseline_func().values()
    metric_name = 'Accuracy' ##'F1 Score'

    _, _, baseline_metrics = zip(*[calculate_classwise_metrics(cm) for cm in baseline_cm_list])
    baseline_f1 = [np.mean([metrics[f"Class {i}"][metric_name] for i in range(2)]) for metrics in baseline_metrics]

    # 2. 计算每个 Stage 的 Macro-F1
    macro_f1_scores = []
    for stage_func, stage_name in zip(stage_functions, stage_names):
        cm_list = stage_func().values()
        _, _, class_metrics = zip(*[calculate_classwise_metrics(cm) for cm in cm_list])
        for metrics in class_metrics:
            avg_f1 = np.mean([metrics[f"Class {i}"][metric_name] for i in range(2)])
            macro_f1_scores.append({"Stage": stage_name, metric_name: avg_f1})


    for f1_value in baseline_f1:
        macro_f1_scores.append({"Stage": "Baseline", metric_name: f1_value})

    # 转换为 DataFrame 并排序
    macro_f1_df = pd.DataFrame(macro_f1_scores)
    stage_order = ["Baseline"] + stage_names
    macro_f1_df["Stage"] = pd.Categorical(macro_f1_df["Stage"], categories=stage_order, ordered=True)
    macro_f1_df = macro_f1_df.sort_values("Stage").reset_index(drop=True)

    # 3. 绘图
    plt.figure(figsize=(10, 6))
    sns.stripplot(x="Stage", y=metric_name, data=macro_f1_df, jitter=True, alpha=0.7, size=2, order=stage_order)
    sns.boxplot(x="Stage", y=metric_name, data=macro_f1_df, showfliers=False, color="white", width=0.4,
                order=stage_order)

    # 4. 计算显著性并标注
    baseline_values = macro_f1_df[macro_f1_df["Stage"] == "Baseline"][metric_name]
    p_values = []
    for stage_name in stage_names:
        stage_values = macro_f1_df[macro_f1_df["Stage"] == stage_name][metric_name]
        stat, p = ttest_ind(stage_values, baseline_values)
        p_values.append((stage_name, p))


    max_y = macro_f1_df[metric_name].max()
    for i, (stage_name, p) in enumerate(p_values):
        if p < 0.05:
            x1, x2 = 0, i + 1  # Baseline 的坐标是 0，其他 Stage 的坐标是 i+1
            y = max_y + 0.02 * (i + 1)
            plt.plot([x1, x2], [y, y], lw=1.5, color="black")
            plt.text((x1 + x2) / 2, y + 0.005, f"p = {p:.1e}", ha="center", va="bottom", fontsize=8)


    plt.title("Macro-F1 Score Comparison Across Stages")
    plt.ylabel("Macro-F1 Score")
    plt.xlabel("Stages")
    plt.ylim(0.7, 1.0)
    plt.grid(axis="y", linestyle="--", alpha=0.7)
    plt.tight_layout()
    plt.savefig('/Users/hwx_admin/Sleep/result/UMAP/classification/macro_f1_vs_baseline.svg')
    plt.show()
def reorder_classes_2_0_1(confusion_matrices):
    reordered_matrices = {}
    for key, cm in confusion_matrices.items():
        cm = np.array(cm)  # 转换为 NumPy 数组
        reordered_cm = cm.copy()

        # 调整行顺序：class 2 -> row 0, class 0 -> row 1, class 1 -> row 2
        reordered_cm = reordered_cm[[2, 0, 1], :]
        # 调整列顺序：class 2 -> col 0, class 0 -> col 1, class 1 -> col 2
        reordered_cm = reordered_cm[:, [2, 0, 1]]

        reordered_matrices[key] = reordered_cm

    return reordered_matrices
stage_functions = [get_stage_0, get_stage_1, get_stage_2, get_stage_3, get_stage_4]
stage_names = ['Stage 0', 'Stage 1', 'Stage 2', 'Stage 3', 'Stage 4']
baseline_func = get_all


# # 调用绘图函数
# cm_list = get_all().values()
# # cm_list = reorder_classes_2_0_1(cm_list).values()
# plot_normalized_confusion_matrix(cm_list, class_labels=['0', '1', '2'])
# # Calculate metrics for each matrix
# metrics = [calculate_classwise_metrics(cm) for cm in cm_list]
#
# # Aggregate metrics by class
# metrics_by_class = {"Class 0": {"Accuracy": [], "Precision": [], "Recall": [], "F1 Score": []},
#                     "Class 1": {"Accuracy": [], "Precision": [], "Recall": [], "F1 Score": []},
#                     "Class 2": {"Accuracy": [], "Precision": [], "Recall": [], "F1 Score": []}}
#
# for _, (_, _, class_metrics_individual) in enumerate(metrics):
#     for class_name, ms in class_metrics_individual.items():
#         metrics_by_class[class_name]["Accuracy"].append(ms["Accuracy"])
#         metrics_by_class[class_name]["Precision"].append(ms["Precision"])
#         metrics_by_class[class_name]["Recall"].append(ms["Recall"])
#         metrics_by_class[class_name]["F1 Score"].append(ms["F1 Score"])

# Plot boxplots
# box_plot_2(metrics_by_class)
#
# all_data = []
# load_path = '/Users/hwx_admin/Sleep/result/UMAP/classification'
# for items in glob.glob(os.path.join(load_path, 'cap_*')):
#     item = np.load(items, allow_pickle=True).item()
#     all_data.append(item)
# get_roc_auc(all_data)
# cm_list = get_stage_1().values()
# metrics = [calculate_classwise_metrics(cm) for cm in cm_list]
# print( [(ac, mf) for ac,mf,_ in metrics])
# cm_list = get_all().values()
# metrics = [calculate_classwise_metrics(cm) for cm in cm_list]
# print( [(ac, mf) for ac,mf,_ in metrics])
# 执行
# plot_f1_scores_vs_baseline_bar(stage_functions, stage_names, baseline_func)

all_data = []
load_path = '/Users/hwx_admin/Sleep/result/UMAP/classification'
for items in glob.glob(os.path.join(load_path, 'cap_*')):
    print(np.load(items, allow_pickle=True))
    item = np.load(items, allow_pickle=True).item()
    all_data.append(item)
get_roc_auc(all_data)
#
# cm_list = get_all().values()
# metrics = [calculate_classwise_metrics(cm) for cm in cm_list]
# print( [(ac, mf) for ac,mf,_ in metrics])

plot_f1_scores_vs_baseline_bar(stage_functions, stage_names, baseline_func, range_len=2)


