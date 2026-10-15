library(naniar)
library(mice) 
library(tableone)
library(ggplot2)
library(lattice)
library(caret)
library(autoReg)
library(dplyr)
library(Matrix)
library(glmnet)
library(Boruta)
library(Hmisc)
library(rms)

#########设置工作目录(数据所在位置以及结果输出位置)#########
setwd("C:\\Users\\LENOVO\\Desktop\\mimic_revise")
if (.Platform$OS.type == "windows") 
{windowsFonts(Times = windowsFont("Times New Roman"))}
par(family = "Times")

#########读取数据#########
data = read.csv("origindata.csv",header = T, encoding = "GBK")
traindata = read.csv("traindata.csv",header = T, encoding = "GBK")
valdata = read.csv("valdata.csv",header = T, encoding = "GBK")

colnames(data) #查看所有变量名
data[,1:21] <- lapply(data[,1:21],as.factor) 
str(data) #查看变量类型是否定义成功

############Boruta筛选变量###############
set.seed(201)
boruta_model <- Boruta(Outcome~.,
                       data=traindata,
                       pValue = 0.01,
                       mcAdj = TRUE,
                       maxRuns = 100,
                       doTrace = 1,  #运算时间比较长，耐心等待，不想看运算过程可以把这个改成0
                       holdHistory = TRUE,
                       getImp = getImpRfZ)
print(boruta_model) # 输出初步筛选结果
plot(boruta_model,
     sort=T, #按重要性排序
     whichShadow=c(T,T,T), #是否画出影子特征，(max shadow,mean shadow,min shadow)
     las=2, #x轴刻度标签90度旋转，1 or 2
     xlab='') #x轴标题把引号里写成自己要写的标题
# 查看变量结果
final_model <- TentativeRoughFix(boruta_model)
print(final_model)
#导出筛选出的最终重要变量的csv表格
selected_features <- getSelectedAttributes(final_model, withTentative = FALSE)
selected_features_df <- data.frame(Variables = selected_features)
write.csv(selected_features_df, "Boruta筛选变量.csv", row.names = FALSE)

##############方差膨胀因子检验#################
Multi_log <- glm(Outcome ~  mech_vent+crrt_24h+antiplatelet+med_status+marital_status_num+age+bun+creatinine+ucr+charlson_score+apsiii+oasis+sapsii+sofa_score+hr+sbp+dbp+spo2+hemoglobin+rbc+wbc+platelets+pt+inr+aptt+anion_gap+glucose
                 , data = traindata, family = binomial)
vif_result <- vif(Multi_log)
print(vif_result)
# 整理VIF结果为表格并导出
vif_table <- as.data.frame(vif_result)
vif_table$Variable <- rownames(vif_table)
vif_table <- vif_table[, c("Variable", setdiff(names(vif_table), "Variable"))]
write.csv(vif_table, "方差膨胀因子(VIF)检验.csv", row.names = FALSE)