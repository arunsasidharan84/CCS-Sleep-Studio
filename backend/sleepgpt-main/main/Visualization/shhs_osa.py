from utils import Bagging
import h5py
import os
import pandas as pd
import numpy as np
def read_subjects(path):
    train_subjects = {}
    test_subjects = {}
    remote = False
    if remote is not True:
        file_path = '/Users/hwx_admin/Downloads/shhs_log/shhs/datasets/shhs1-dataset-0.21.0.csv'
    else:
        file_path = '/home/cuizaixu_lab/huangweixuan/Sleep/data/shhs_new/shhs1-dataset-0.21.0.csv'
    data = pd.read_csv(file_path)
    column_name = ['nsrrid', 'ahi_a0h3', 'ahi_a0h4', 'ahi_a0h4a', 'ahi_c0h4', 'ahi_c0h4a', 'ahi_o0h4', 'ahi_o0h4a']

    with h5py.File(os.path.join(path, 'concat_subjects_c2_new.h5'), 'r') as h5_file:
        train_no_subjects = h5_file['train']["0"][:]
        # train_osa_subjects = h5_file['train']["2"][:]
        train_mid_subjects = h5_file['train']["1"][:]
        test_no_subjects = h5_file['test']["0"][:]
        # test_osa_subjects = h5_file['test']["2"][:]
        test_mid_subjects = h5_file['test']["1"][:]
        train_subjects["0"] =  [s.decode('utf-8') for s in train_no_subjects]
        # train_subjects["2"]  =  [s.decode('utf-8') for s in train_osa_subjects]
        train_subjects["1"]  =  [s.decode('utf-8') for s in train_mid_subjects]
        # for name in train_subjects['1']:
        #     print(data[data['nsrrid'] == int(name)]['ahi_a0h4a'].values)
        test_subjects["0"] = [s.decode('utf-8') for s in test_no_subjects]
        # test_subjects["2"] = [s.decode('utf-8') for s in test_osa_subjects]
        test_subjects["1"]  =  [s.decode('utf-8') for s in test_mid_subjects]
        for name in test_subjects['1']:
            print(data[data['nsrrid'] == int(name)]['ahi_a0h4a'].values)

    return train_subjects, test_subjects

if __name__  == '__main__':
    confusion_matrix_res = {}
    train_subjects,test_subjects = read_subjects('../../result/UMAP/shhs1_osa')
    param_grid_rf = {
        'n_estimators': [500],
        'max_depth': [50],
        'min_samples_split': [10],
        'min_samples_leaf': [4],
        'class_weight': ['balanced']
    }

    param_grid_svm = {
        'C': [0.1, 1, 10],
        'kernel': ['linear', 'poly', 'rbf'],
        'gamma': ['scale', 'auto']
    }

    param_grid_knn = {
        'n_neighbors': [3, 5, 7],
        'weights': ['uniform', 'distance'],
        'metric': ['minkowski', 'euclidean']
    }
    param_grid_xgb = {
        'n_estimators': [50],
        'max_depth': [3],
        'learning_rate': [0.1],
    }
    # for random_state in range(0, 10):
    #     pipeline = Bagging.SleepDisorderPipeline(
    #         num_channels=4,
    #         h5_file_path='../../result/UMAP/shhs1_osa/concat_data_c2_new.h5',
    #         label_mapping={"0": 0, "1": 1},
    #         model_type='nn',
    #         random_state=random_state,
    #         train_subjects=train_subjects, test_subjects=test_subjects,
    #         exclude_c = None,
    #         reshape=True,
    #         select_stages=[0,1,2,3,4],
    #         lr_rate=0.00075,
    #     )
    #
    #     confusion_matrixes = pipeline.run_pipeline(selected_stage="0", split_method="kfold",
    #                                                n_splits=4, param_grid=param_grid_rf)
    #     confusion_matrix_res[random_state] = confusion_matrixes
    # print(confusion_matrix_res)
    # 设定不同的 stage 组合
    stage_combinations = [
        [1, 2, 3, 4],
        [0, 2, 3, 4],
        [0, 1, 3, 4],
        [0, 1, 2, 4],
        [0, 1, 2, 3]
    ]
    save_path = "../../result/UMAP/shhs1_osa/confusion_matrix_results.xlsx"
    os.makedirs(os.path.dirname(save_path), exist_ok=True)
    # 打开 ExcelWriter
    with pd.ExcelWriter(save_path, engine="openpyxl") as writer:
        for select_stages in stage_combinations:
            confusion_matrix_res = {}

            # 运行 10 次
            for random_state in range(10):
                pipeline = Bagging.SleepDisorderPipeline(
                    num_channels=4,
                    h5_file_path='../../result/UMAP/shhs1_osa/concat_data_c2_new.h5',
                    label_mapping={"0": 0, "1": 1},
                    model_type='nn',
                    random_state=random_state,
                    train_subjects=train_subjects,
                    test_subjects=test_subjects,
                    exclude_c=None,
                    reshape=True,
                    select_stages=select_stages,
                    lr_rate=0.0005,
                )

                confusion_matrixes = pipeline.run_pipeline(
                    selected_stage="0",
                    split_method="kfold",
                    n_splits=4,
                    param_grid=param_grid_rf
                )
                confusion_matrix_res[random_state] = confusion_matrixes

            # === 将结果写入 Excel ===
            # 展开每个随机种子的矩阵，保存为 DataFrame
            all_rows = []
            for rs, cm in confusion_matrix_res.items():
                cm = np.array(cm)
                cm_flat = cm.flatten()
                n = cm.shape[0]
                col_names = [f"C{r}_Pred{c}" for r in range(n) for c in range(n)]
                df = pd.DataFrame([cm_flat], columns=col_names)
                df.insert(0, "random_state", rs)
                all_rows.append(df)

            # 合并所有 random_state 结果
            stage_df = pd.concat(all_rows, ignore_index=True)
            sheet_name = "Stages_" + "".join(map(str, select_stages))
            stage_df.to_excel(writer, sheet_name=sheet_name, index=False)

            print(f"✅ 已保存 {sheet_name} 的混淆矩阵结果，共 {len(confusion_matrix_res)} 个随机种子。")

    print(f"\n🎯 所有结果已保存到: {save_path}")