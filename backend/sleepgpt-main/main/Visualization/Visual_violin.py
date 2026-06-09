import os
import torch
import glob
import numpy as np
import seaborn as sns
import matplotlib.pyplot as plt
import pandas as pd
from scipy import stats
channel_name = ["C3", "C4", "EMG", "EOG", "F3", "Fpz", "O1", "Pz"]
def get_all_dataset_reconstruction_result(root_path):
    dataset_list_path = os.listdir(root_path)
    print(f"dataset_list_path : {dataset_list_path}")
    mode = ['visual_mask_same', 'visual_mask_no_fft', 'visual_all']
    res = {}
    res_name = {}
    for dst_path in dataset_list_path:
        if dst_path in mode:
            if dst_path not in res:
                res[dst_path] = {}
                res_name[dst_path] = {}
            for items in glob.glob(os.path.join(root_path, dst_path, '*/*/*')):
                ckpt = torch.load(items, map_location='cpu')
                dst_name = items.split('/')[-3]
                if dst_name not in res[dst_path]:
                    res[dst_path][dst_name] = {'loss': [], 'loss2': []}
                    res_name[dst_path][dst_name] = []
                for n, v in ckpt.items():
                    res[dst_path][dst_name]['loss'].append(v['loss1'])
                    res[dst_path][dst_name]['loss2'].append(v['loss2'])
                    res_name[dst_path][dst_name].append(n)
    return res, res_name
# 处理数据，创建DataFrame
def prepare_data(data, loss_type):
    all_data = []
    for dataset_name, losses in data.items():
        for tensor in losses[loss_type]:
            for channel, value in enumerate(tensor.numpy()):
                all_data.append((dataset_name, channel, value))
    df = pd.DataFrame(all_data, columns=['Dataset', 'Channel', 'Value'])
    df['Channel'] = df['Channel'].astype('category')  # Ensure that Channel is a categorical type
    return df
# 示例函数来清除离群点
def remove_outliers_z(df, column):
    df['z_score'] = stats.zscore(df[column])
    # 保留Z-Score在正负3之内的数据
    df_clean = df[df['z_score'].abs() <= 3]
    df_clean = df_clean.drop(columns=['z_score'])
    return df_clean
def remove_outliers_iqr(df, column):
    Q1 = df[column].quantile(0.25)
    Q3 = df[column].quantile(0.75)
    IQR = Q3 - Q1
    df_clean = df[(df[column] >= (Q1 - 1.5 * IQR)) & (df[column] <= (Q3 + 1.5 * IQR))]
    return df_clean



def create_separate_violin_plots(df):
    # 获取通道列表
    channels = df['Channel'].unique()

    for loss_name in ['loss', 'loss2']:
        for channel in channels:
            channel_df = df[df['Channel'] == channel]
            plt.figure(figsize=(12, 6))
            sns.violinplot(x='Dataset', y=loss_name, data=channel_df)
            plt.title(f'Violin Plot for Channel {channel}')
            plt.xlabel('Dataset')
            plt.ylabel('Value')

            mean_values = channel_df.groupby('Dataset')[loss_name].mean().values
            print(mean_values)
            plt.scatter(range(len(mean_values)), mean_values, color='red', zorder=3)
            plt.show()

DATASET_ORDER = ['EDF','MASS1','MASS2','MASS3','MASS4','MASS5','SHHS1','physio_train']

# 通道配色（可按需改）
PALETTE = {
    'EDF':        '#6baed6',
    'MASS1':      '#9ecae1',
    'MASS2':      '#c6dbef',
    'MASS3':      '#3182bd',
    'MASS4':      '#9e9ac8',
    'MASS5':      '#756bb1',
    'SHHS1':      '#31a354',
    'physio_train':'#e6550d',
}

def FacetGris(df):
    """
    期待 df 至少包含：['Dataset', 'Channel', 'loss', 'loss2'] 或其中一个 loss 列。
    每个通道一行（row），x 轴是 Dataset；按 Dataset 顺序画 violin，叠加均值点。
    """
    # 清理异常值，避免 seaborn 在 KDE 时崩溃
    df = df.copy()
    loss_cols = [c for c in ['loss','loss2'] if c in df.columns]
    if not loss_cols:
        raise ValueError("df 中找不到 'loss' 或 'loss2' 列。请检查列名。")

    # 丢 NaN/Inf
    for c in loss_cols:
        df[c] = pd.to_numeric(df[c], errors='coerce')
    df = df.replace([np.inf, -np.inf], np.nan)
    df = df.dropna(subset=loss_cols + ['Dataset','Channel'])

    # 统一类别顺序
    if 'Dataset' in df.columns:
        df['Dataset'] = pd.Categorical(df['Dataset'], categories=DATASET_ORDER, ordered=True)

    sns.set_theme(style="whitegrid", context="talk")

    for loss_name in loss_cols:
        # 过滤掉全空/单点的分组（KDE 对极少样本会不稳）
        valid = []
        for (ds, ch), g in df.groupby(['Dataset','Channel']):
            # 保证这一格至少有 2 个样本（KDE 更稳）
            if g[loss_name].notna().sum() >= 2:
                valid.append(g)
        if not valid:
            print(f"[WARN] 所有分组在 {loss_name} 下样本不足，跳过此图")
            continue
        dplot = pd.concat(valid, ignore_index=True)

        # 用 catplot(kind='violin')：官方推荐，内部比 FacetGrid+map 安全
        g = sns.catplot(
            kind='violin',
            data=dplot,
            x='Dataset', y=loss_name,
            row='Channel',
            order=DATASET_ORDER,
            inner='box', cut=0, scale='width',  # 更稳健的核密度设置
            palette=PALETTE,
            sharex=True, sharey=False,
            height=2.2, aspect=3.8
        )

        # 给每个子图叠加均值点（不再用 map_dataframe，直接操作 axes 更稳）
        for ch, ax in g.axes_dict.items():
            # ch 是当前 row 的 Channel 名称
            sub = dplot[dplot['Channel'] == ch]
            if sub.empty:
                continue
            means = sub.groupby('Dataset', observed=False)[loss_name].mean().reindex(DATASET_ORDER)
            # 只画有数据的类别
            mask = means.notna()
            xs = np.arange(len(DATASET_ORDER))[mask]
            ys = means[mask].values
            ax.scatter(xs, ys, s=18, c='red', zorder=5, label='Mean')
            # 可选：只保留一次图例
            handles, labels = ax.get_legend_handles_labels()
            if 'Mean' in labels:
                ax.legend_.remove() if ax.legend_ else None

        # 统一标题 & 网格细节
        g.set_titles(row_template="{row_name}")
        for ax in g.axes.flat:
            ax.grid(True, axis='y', linestyle='--', linewidth=0.6, alpha=0.6)

        plt.subplots_adjust(hspace=0.45)
        plt.show()
        plt.close(g.fig)  # 很重要：关闭图，避免内存累积导致崩溃

def ckpt_plot(ckpt_path, ):
    # Load the checkpoint file
    checkpoint = torch.load(ckpt_path, map_location=torch.device('cpu'))
    # Process the checkpoint data to prepare it for violin plots
    data_frames = {}
    for dataset_name, losses in checkpoint.items():
        for loss_name, values_list in losses.items():
            # Flatten the list of tensors and concatenate them along the first axis
            values = torch.stack(values_list, dim=0).numpy()

            # Create a DataFrame
            df = pd.DataFrame(values, columns=[f'Channel_{channel_name[i]}' for i in range(values.shape[1])])
            df = df.melt(var_name='Channel', value_name=loss_name)
            df['Dataset'] = dataset_name

            # Store the DataFrame in a dictionary
            data_frames[(dataset_name, loss_name)] = df

    # Combine all the DataFrames for violin plots
    all_df = pd.concat(data_frames.values(), ignore_index=True)

    # Remove outliers using IQR
    # Calculate Q1, Q3, and IQR for each loss type
    for loss_name in checkpoint[next(iter(checkpoint))].keys():
        q1 = all_df[loss_name].quantile(0.25)
        q3 = all_df[loss_name].quantile(0.75)
        print(q1, q3)
        iqr = q3 - q1
        # Filter out the outliers
        all_df = all_df[~((all_df[loss_name] < (q1 - 1.5 * iqr)) | (all_df[loss_name] > (q3 + 1.5 * iqr)))]
    # create_separate_violin_plots(all_df)
    print('finished preparation')
    FacetGris(all_df)

def main():
    data, name = get_all_dataset_reconstruction_result('../../temp_log/other')
    data = data['visual_mask_same']
    for loss_type in ['loss', 'loss2']:
        df = prepare_data(data, loss_type)
        df_clean = remove_outliers_iqr(df, 'Value')
        plt.figure(figsize=(12, 6))
        sns.violinplot(x='Dataset', y='Value', hue='Channel', data=df_clean)
        plt.title(f'Violin plot for {loss_type}')
        plt.legend(title='Channel')
        plt.show()


if __name__ == '__main__':
    main()
    #
    # ckpt_plot(ckpt_path='../../temp_log/other/violin.ckpt')
