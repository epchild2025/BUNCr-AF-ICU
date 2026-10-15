import warnings
warnings.filterwarnings("ignore")
import os
import pandas as pd
from sklearn.preprocessing import StandardScaler
import statsmodels.api as sm
from sklearn.metrics import confusion_matrix, roc_curve, auc, roc_auc_score
import pickle
from sklearn.tree import DecisionTreeClassifier, plot_tree
from sklearn.ensemble import RandomForestClassifier
import numpy as np
from xgboost import XGBClassifier
import lightgbm as lgb
from sklearn.svm import SVC
from sklearn.neural_network import MLPClassifier
import matplotlib.pyplot as plt
from sklearn.metrics import brier_score_loss
from sklearn.utils import resample
import seaborn as sns
from scipy.stats import norm
from sklearn.calibration import calibration_curve
import shap
from statsmodels.nonparametric.smoothers_lowess import lowess
from sklearn.model_selection import GridSearchCV
from sklearn.metrics import cohen_kappa_score
from sklearn.linear_model import LogisticRegression
from imblearn.ensemble import BalancedBaggingClassifier

####################### 一、数据导入及预处理 #######################
os.chdir( )# 设置当前工作路径
print("当前工作路径：", os.getcwd())# 检查当前路径是否设置成功
plt.rcParams['font.family'] = 'Times New Roman' # 设置字体为Times New Roman，与r统一
# 导入数据
train_data = pd.read_csv("traindata.csv", encoding="GBK")   
val_data = pd.read_csv("valdata.csv", encoding="GBK")

##############################################################################
####################### 二、在训练集构建机器学习预测模型 #######################
###############################################################################
############################## 1.Logistic回归模型 ###############################
train_data = pd.read_csv("traindata.csv", encoding="GBK")  
print(train_data.info()) 
categorical_vars = train_data.iloc[:, 0:21].columns.tolist() # 定义分类变量
for var in categorical_vars:
    train_data[var] = train_data[var].astype('category') 
# 查看训练集数据变量类型是否定义成功
print(train_data.info()) 
# 定义模型关键变量 
X_train = train_data[['mech_vent','crrt_24h','med_status','age','ucr','charlson_score','apsiii','oasis','sapsii','sofa_score','hr','spo2','rbc','wbc','platelets','glucose']] 
X_train_const = sm.add_constant(X_train) 
Y_train = train_data['Outcome'] # 定义结局变量
# 开始训练模型 
logist_model = sm.Logit(Y_train, X_train_const).fit(disp=0)
logist_model.summary() 
Y_train_logist = logist_model.predict(X_train_const) 
auc_logist = roc_auc_score(Y_train, Y_train_logist) 
auc_logist # 输出训练集AUC
############################### 2. 决策树模型 ###############################
# 定义训练集和验证集里的自变量和结局
train_data_ml = pd.read_csv("traindata.csv", encoding="GBK")    # 想用过采样的训练集的话需要改名字⭐⭐⭐
val_data_ml = pd.read_csv("valdata.csv", encoding="GBK")
X_train = train_data_ml[['mech_vent','crrt_24h','med_status','age','ucr','charlson_score','apsiii','oasis','sapsii','sofa_score','hr','spo2','rbc','wbc','platelets','glucose']] # 批量定义自变量
y_train = train_data_ml['Outcome'] 
X_val = val_data_ml[['mech_vent','crrt_24h','med_status','age','ucr','charlson_score','apsiii','oasis','sapsii','sofa_score','hr','spo2','rbc','wbc','platelets','glucose']] # 批量定义自变量
y_val = val_data_ml['Outcome'] 

# 设置环境变量，避免路径问题
os.environ['JOBLIB_TEMP_FOLDER'] = '/tmp'

tree_default = DecisionTreeClassifier(random_state=123)  # 创建决策树分类模型，使用默认参数
tree_default.fit(X_train, y_train)  # 在训练集上拟合决策树模型
print("决策树模型默认参数:", pd.DataFrame.from_dict(tree_default.get_params(), orient='index'))
y_val_pred_prob_treed = tree_default.predict_proba(X_val)[:, 1]
auc_treed = roc_auc_score(y_val, y_val_pred_prob_treed)
print("默认参数决策树模型的验证集 AUC:", auc_treed)

# 1. 定义超参数搜索范围
param_grid = {
    'max_depth': [3, 5, 10, None],  
    'min_samples_split': [5, 10, 20],  
    'max_features': ['sqrt', None],  
    'ccp_alpha': [0.0, 0.01, 0.1]  
}

# 2. 使用 GridSearchCV 进行网格搜索和 k 折交叉验证
grid_search_tree = GridSearchCV(
    estimator=tree_default,
    param_grid=param_grid,
    scoring='roc_auc',  # 使用 AUC 作为评价指标
    cv=5,  # 5 折交叉验证
    n_jobs=1,  # 使用单线程
    verbose=1
)

grid_search_tree.fit(X_train, y_train)  # 在训练集上进行网格搜索

# 3. 输出最优超参数
best_auc_tree = grid_search_tree.best_score_  # 获取最佳模型的交叉验证 AUC
tree_model_best = grid_search_tree.best_estimator_  # 获取最佳模型
best_params = grid_search_tree.best_params_  # 获取最佳超参数组合
print("最佳决策树模型参数组合:", best_params)
print("调优后决策树模型详细参数:", pd.DataFrame.from_dict(tree_model_best.get_params(), orient='index'))
print("参数调优决策树模型最佳模型的交叉验证 AUC:", best_auc_tree)
print("默认参数决策树模型的验证集 AUC:", auc_treed)
############################### 3. 随机森林模型 ###############################
# 首先用默认参数训练随机森林模型
rf_model_default = RandomForestClassifier(random_state=123)
rf_model_default.fit(X_train, y_train)
# 查看模型默认参数
print("模型默认参数:", pd.DataFrame.from_dict(rf_model_default.get_params(), orient='index'))
# 计算默认参数模型的验证集AUC
y_val_pred_prob_rfd = rf_model_default.predict_proba(X_val)[:, 1]
auc_rfd = roc_auc_score(y_val, y_val_pred_prob_rfd)
print("默认参数模型的验证集 AUC:", auc_rfd)

# 进行超参数网格搜索调优
# 1. 定义超参数搜索范围
param_grid = {
    'n_estimators': [100, 200],  
    'max_depth': [3, 5, 8, 10],  
    'min_samples_split': [20, 50, 80],  
    'min_samples_leaf': [10, 20, 40],   
    'max_features': ['sqrt', 'log2'],  
    'max_samples': [0.7, 0.85]   
}

# 2. 使用 GridSearchCV 进行网格搜索和 k 折交叉验证
grid_search_rf = GridSearchCV(
    estimator=rf_model_default,  
    param_grid=param_grid,  
    scoring='roc_auc',  
    cv=5,  
    n_jobs=-1,  
    verbose=1
)

grid_search_rf.fit(X_train, y_train)

# 3. 输出最优超参数
best_auc_rf = grid_search_rf.best_score_  # 获取最佳模型的交叉验证 AUC
rf_model_best = grid_search_rf.best_estimator_  # 获取最佳模型
best_params_rf = grid_search_rf.best_params_  # 获取最佳超参数组合
best_ntree = best_params_rf['n_estimators']
best_mtry = best_params_rf['max_features']
print("最佳RF模型参数组合: n_estimators =", best_ntree, ", max_features =", best_mtry)
print("调优后RF模型详细参数:", pd.DataFrame.from_dict(rf_model_best.get_params(), orient='index'))
print("默认参数RF模型的验证集 AUC:", auc_rfd)
print("调优后RF模型最佳模型的交叉验证 AUC", best_auc_rf)
###################### 4. Xgboost模型 ##########################
# 使用默认参数训练XGBoost
xgb_default = XGBClassifier(random_state=123, eval_metric='logloss')
xgb_default.fit(X_train, y_train)
# 计算默认参数模型的验证集AUC
y_val_pred_prob_xgbd = xgb_default.predict_proba(X_val)[:, 1]
auc_xgbd = roc_auc_score(y_val, y_val_pred_prob_xgbd)
print("默认参数XGBoost模型的验证集 AUC:", auc_xgbd)

# 定义超参数搜索范围
param_grid = {
    'learning_rate': [0.01, 0.05, 0.1],  # 学习率
    'max_depth': [3, 4, 6],  # 最大深度
    'min_child_weight': [1, 3, 5],
    'n_estimators': [100, 200, 300],  # 弱分类器数量
    'subsample': [0.8],  # 采样比例
    'colsample_bytree': [0.7, 0.8]
}

# 使用 GridSearchCV 进行网格搜索和 k 折交叉验证
grid_search_xgb = GridSearchCV(
    estimator=xgb_default,  # 使用之前定义的默认参数模型
    param_grid=param_grid,  # 使用之前定义的超参数网格
    scoring='roc_auc',  # 使用 AUC 作为评价指标
    cv=5,  # 5 折交叉验证
    n_jobs=-1,  # 并行计算
    verbose=1
)

grid_search_xgb.fit(X_train, y_train)  # 在训练集上进行网格搜索

# 输出最优超参数组合
best_auc_xgb = grid_search_xgb.best_score_  # 获取最佳模型的交叉验证 AUC
xgb_model_best = grid_search_xgb.best_estimator_  # 获取最佳模型
best_params_xgb = grid_search_xgb.best_params_  # 获取最佳超参数组合
print("最佳XGBoost参数组合:", best_params_xgb)
print("调优后XGBoost模型详细参数:", pd.DataFrame.from_dict(xgb_model_best.get_params(), orient='index'))
print("默认参数XGBoost模型的验证集 AUC:", auc_xgbd)
print("参数调优XGBoost模型最佳模型的交叉验证 AUC:", best_auc_xgb)
###################### 5. LightGBM模型 ##########################
# 使用默认参数训练LightGBM
lgb_default = lgb.LGBMClassifier(random_state=123)
lgb_default.fit(X_train, y_train)
# 计算默认参数模型的验证集AUC
y_val_pred_prob_lgbd = lgb_default.predict_proba(X_val)[:, 1]
auc_lgbd = roc_auc_score(y_val, y_val_pred_prob_lgbd)
print("默认参数LightGBM模型的验证集 AUC:", auc_lgbd)

# 定义超参数搜索范围
param_grid = {
    'learning_rate': [0.01, 0.05, 0.1],  # 学习率
    'num_leaves': [15, 31, 45],  # 叶子节点数
    'n_estimators': [100, 200],  # 弱分类器数量
    'max_depth': [3, 5, 7],
    'min_child_samples': [20, 50],
    'subsample': [0.8],  # 采样比例
    'colsample_bytree': [0.8]  # 特征子集采样比例
}

# 使用 GridSearchCV 进行网格搜索和 k 折交叉验证
grid_search_lgb = GridSearchCV(
    estimator=lgb_default,  # 使用之前定义的默认参数模型
    param_grid=param_grid,  # 使用之前定义的超参数网格
    scoring='roc_auc',  # 使用 AUC 作为评价指标
    cv=5,  # 5 折交叉验证
    n_jobs=-1,  # 并行计算
    verbose=1
)

grid_search_lgb.fit(X_train, y_train)  # 在训练集上进行网格搜索

# 输出最优超参数组合
best_auc_lgb = grid_search_lgb.best_score_  # 获取最佳模型的交叉验证 AUC
lgb_model_best = grid_search_lgb.best_estimator_  # 获取最佳模型
best_params_lgb = grid_search_lgb.best_params_  # 获取最佳超参数组合
print("最佳LightGBM参数组合:", best_params_lgb)
print("调优LightGBM模型详细参数:", pd.DataFrame.from_dict(lgb_model_best.get_params(), orient='index'))
print("默认参数LightGBM模型的验证集 AUC:", auc_lgbd)
print("参数调优LightGBM模型最佳模型的交叉验证 AUC:", best_auc_lgb)