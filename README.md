# SAFE-ICU：随机森林网页版本

本版本使用重新分析后的固定随机森林模型，预测老年房颤ICU患者的院内死亡。预测时点为ICU入住后24小时，适用于在该时点仍符合研究入选条件的患者。

## 上传GitHub

将以下文件放在GitHub仓库同一个目录，建议仓库根目录：

- `app.py`：网页主体。
- `predictor_SHAP.py`：兼容原有Streamlit入口，转到新版网页。
- `rf_predictor.py`：模型读取、输入检查、预测和SHAP处理。
- `rf_model.pkl`：已核对的最终随机森林，约5 MB。
- `requirements.txt`：部署依赖版本。
- `README.md`：本说明。
- `.gitignore`：排除本地测试文件。

本地测试环境、旧版备份及任何患者数据不在上传包内。旧XGBoost模型不是本网页的运行依赖。检查仓库是否还存在旧的`environment.yml`、`Pipfile`或其他依赖配置，避免与本版本的`requirements.txt`冲突。

## Streamlit部署

1. 上传并提交上述文件。
2. Streamlit中选择仓库、分支和入口文件。新部署推荐`app.py`；原部署若使用`predictor_SHAP.py`，可以保留该入口，因为已提供兼容文件。
3. 在Advanced settings中选择Python **3.12**。不要把Python版本写进requirements.txt。
4. 部署后试填输入并点击Predict，核查院内死亡概率、分类和SHAP图。

依赖和Python环境选择参见[Streamlit官方说明](https://docs.streamlit.io/deploy/concepts/dependencies)。模型保存时使用scikit-learn 1.8.0，本版本固定同一版本，避免跨版本加载问题，参见[scikit-learn模型保存说明](https://scikit-learn.org/stable/model_persistence.html)。

本地运行：

```bash
python -m pip install -r requirements.txt
python -m streamlit run app.py
```

## 与训练模型一致的16个输入

| 模型字段 | 页面含义及单位 |
|---|---|
| mech_vent | ICU首24小时机械通气，0/1 |
| crrt_24h | ICU首24小时肾脏替代治疗，0/1 |
| med_status | 与ICU首24小时重叠的抗栓处方：0均无，1仅抗血小板，2抗凝（可同时抗血小板） |
| age | 年龄，岁；≥65 |
| ucr | BUN/Cr；BUN与Cr均以mg/dL计算 |
| charlson_score | Charlson合并症评分 |
| apsiii | APS III评分 |
| oasis | OASIS评分 |
| sapsii | SAPS II评分 |
| sofa_score | 首日SOFA评分 |
| hr | ICU首24小时心率均值，beats/min |
| spo2 | ICU首24小时SpO2均值，% |
| rbc | 首个符合条件的红细胞计数，10¹²/L |
| wbc | 首个符合条件的白细胞计数，10⁹/L |
| platelets | 首个符合条件的血小板计数，10⁹/L |
| glucose | 首个符合条件的血糖，mg/dL |

实验室数值使用ICU首24小时内、预测时点前已可获得的首个合格结果，与本次提取SQL一致。评分按研究使用的首日衍生评分定义输入。必需输入需完整填写，本网页没有新增缺失值插补模型，也没有自动进行标准化或单位转换。

## 已修改的逻辑

- 读取rf_model.pkl，不重新训练模型。路径相对于代码文件，可从不同工作目录启动。
- 核查模型SHA-256、类型、特征名称及顺序、结局类别，避免误上传旧模型。
- 删除旧26变量表单，使用当前模型实际16变量。
- 将1年死亡改为院内死亡，删除旧版模型直接给出的治疗建议。
- 用死亡类别（1）的概率输出；以最佳F1阈值**0.21747200428484978**进行分类，显示21.75%。不再调用默认model.predict作为风险分类。
- 较低风险患者仍显示死亡概率，而非将存活概率误写为死亡概率。
- RF SHAP明确选择死亡类别；核查baseline＋各贡献之和与死亡概率一致。SHAP表达模型贡献，不代表因果。
- 可下载文字和路径可编辑的SVG解释图，没有PDF导出。
- 显示原RF输出，未使用外部队列拟合的重校准系数。

## 模型身份

SHA-256：`8fe2acc54c4d9e79218b4fa9b45150eb9344120c1016d475a1f8dcbe6f2b4ba7`。

模型训练结果未改写。需要换模型时，应同步更新模型身份、变量和验证结果，而不能只替换文件名。

## 新版模型更新

新版模型的类型、16个输入及其顺序、类别[0,1]、scikit-learn保存版本1.8.0均与网页一致。更新了模型SHA-256和最佳F1阈值，并以模型身份作为Streamlit缓存参数，避免模型更新后继续复用旧缓存。

最佳F1阈值由当前模型和当前valdata.csv核对得到：0.21747200428484978。Excel写出的0.2174720042848498存在末位浮点舍入差异；采用预测概率中的原始阈值以保持边界患者分类一致。

新版内部验证：3,865人、567例死亡；AUC=0.8018739378149121，最佳F1=0.46291208791208793，较高风险人数889。以上只读核查未重训模型。新版SHAP页面尚未重新运行完整测试，输入类型和解释接口与原版相同。

重新上传app.py、rf_predictor.py及rf_model.pkl到GitHub同一目录，然后重启Streamlit应用。入口app.py或predictor_SHAP.py均可，Python保持3.12，requirements.txt保持当前版本。README.md同步更新。
