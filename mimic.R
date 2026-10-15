library(naniar)
library(ggplot2)
library(caret)
library(dplyr)

######### 设置工作目录 #########
setwd()

if (.Platform$OS.type == "windows") {
  windowsFonts(Times = windowsFont("Times New Roman"))
}

######### 读取未插补的原始数据 #########
data <- read.csv(
  "origindata.csv",
  header = TRUE,
  fileEncoding = "GBK",
  stringsAsFactors = FALSE,
  check.names = FALSE,
  na.strings = c("", "NA", "NaN", "NULL", "null", "N/A"),
  strip.white = TRUE
)

if (anyDuplicated(names(data))) {
  stop("数据存在重复列名，请先核查。")
}
if (!"Outcome" %in% names(data)) {
  stop("数据缺少 Outcome 列。")
}
if (ncol(data) < 17L) {
  stop("数据不足17列，请核查分类变量的范围。")
}

# 沿用原代码：前17列为分类变量。
# 请确认这些列确实都是分类变量，尤其不能包含连续型 ucr。
categorical_vars <- setdiff(names(data)[1:21], "Outcome")

# 明确排除患者和医院标识，避免作为预测变量参与建模。
id_vars <- intersect(
  c("subject_id", "hadm_id", "stay_id", "patientunitstayid",
    "hospital_stay_id", "hospitalid", "uniquepid"),
  names(data)
)

predictor_vars <- setdiff(names(data), c("Outcome", id_vars))
categorical_vars <- intersect(categorical_vars, predictor_vars)
continuous_vars <- setdiff(predictor_vars, categorical_vars)

# 结局必须完整且编码为0/1，不插补结局。
outcome <- suppressWarnings(as.numeric(as.character(data$Outcome)))
if (anyNA(outcome) || any(!outcome %in% c(0, 1))) {
  stop("Outcome 必须完整且编码为0/1。")
}
if (length(unique(outcome)) != 2L) {
  stop("Outcome 必须同时包含0和1。")
}
data$Outcome <- factor(outcome, levels = c(0, 1))

# 整理分类变量；类别水平稍后只从训练集确定。
for (v in categorical_vars) {
  x <- trimws(as.character(data[[v]]))
  x[!is.na(x) & x == ""] <- NA_character_
  data[[v]] <- x
}

# 连续变量转换为数值，避免把转换错误静默当作缺失。
for (v in continuous_vars) {
  original <- data[[v]]
  numeric_value <- suppressWarnings(as.numeric(as.character(original)))
  
  if (any(!is.na(original) & is.na(numeric_value))) {
    stop("连续变量 ", v, " 含非数值内容，请核查变量类型或原始数据。")
  }
  if (any(!is.na(numeric_value) & !is.finite(numeric_value))) {
    stop("连续变量 ", v, " 含无穷值，请先核查。")
  }
  
  data[[v]] <- numeric_value
}

############################################
######### 第一步：原始数据先划分 #########
############################################

set.seed(201)

inTrain <- as.integer(
  createDataPartition(
    y = data$Outcome,
    p = 0.7,
    list = FALSE
  )
)

inValidation <- setdiff(seq_len(nrow(data)), inTrain)

traindata_raw <- data[inTrain, , drop = FALSE]
valdata_raw <- data[inValidation, , drop = FALSE]

write.csv(
  data.frame(
    Original_Row = seq_len(nrow(data)),
    Dataset = ifelse(
      seq_len(nrow(data)) %in% inTrain,
      "Training",
      "Internal validation"
    )
  ),
  "数据划分记录.csv",
  row.names = FALSE,
  fileEncoding = "GBK"
)

############################################
######### 第二步：报告插补前缺失率 #########
############################################

missing_report <- function(df, dataset_name) {
  data.frame(
    Dataset = dataset_name,
    Variable = predictor_vars,
    N = nrow(df),
    Missing_N = vapply(
      df[predictor_vars],
      function(x) sum(is.na(x)),
      integer(1)
    ),
    Missing_Ratio = vapply(
      df[predictor_vars],
      function(x) mean(is.na(x)),
      numeric(1)
    ),
    row.names = NULL
  )
}

missing_ratio_df <- rbind(
  missing_report(data, "Overall"),
  missing_report(traindata_raw, "Training"),
  missing_report(valdata_raw, "Internal validation")
)

write.csv(
  missing_ratio_df,
  "缺失值比例_插补前.csv",
  row.names = FALSE,
  fileEncoding = "GBK"
)

missing_plot <- traindata_raw[predictor_vars] %>%
  gg_miss_var(show_pct = TRUE) +
  theme_bw(base_size = 16, base_family = "Times") +
  labs(title = "训练集插补前缺失情况")

print(missing_plot)

############################################
######### 第三步：仅按训练集缺失率筛选 #########
############################################

missing_threshold <- 0.20

train_missing <- vapply(
  traindata_raw[predictor_vars],
  function(x) mean(is.na(x)),
  numeric(1)
)

retained_vars <- predictor_vars[train_missing <= missing_threshold]
excluded_vars <- setdiff(predictor_vars, retained_vars)

if (!length(retained_vars)) {
  stop("按训练集缺失率筛选后没有可用预测变量。")
}

write.csv(
  data.frame(
    Variable = predictor_vars,
    Training_Missing_Ratio = unname(train_missing),
    Retained = predictor_vars %in% retained_vars
  ),
  "训练集缺失率筛选记录.csv",
  row.names = FALSE,
  fileEncoding = "GBK"
)

if (length(excluded_vars)) {
  message(
    "训练集缺失率超过20%，已剔除：",
    paste(excluded_vars, collapse = ", ")
  )
}

retained_categorical <- intersect(categorical_vars, retained_vars)
retained_continuous <- intersect(continuous_vars, retained_vars)

# 输出中保留结局和预测变量；ID另存于原始数据及划分记录。
output_vars <- c("Outcome", retained_vars)

traindata <- traindata_raw[output_vars]
valdata <- valdata_raw[output_vars]

############################################
######### 第四步：训练集估计单次插补规则 #########
############################################

# 连续变量：训练集中位数。
# 分类变量：训练集众数；出现并列众数时按字符排序取第一个。
# 验证集使用同一套规则，不计算验证集自己的中位数或众数。
imputation_rules <- list(
  continuous = list(),
  categorical = list(),
  category_levels = list()
)

for (v in retained_continuous) {
  fill_value <- median(traindata[[v]], na.rm = TRUE)
  
  if (!is.finite(fill_value)) {
    stop("训练集变量 ", v, " 无法计算有效中位数。")
  }
  
  imputation_rules$continuous[[v]] <- fill_value
  
  traindata[[v]][is.na(traindata[[v]])] <- fill_value
  valdata[[v]][is.na(valdata[[v]])] <- fill_value
}

for (v in retained_categorical) {
  observed <- traindata[[v]][!is.na(traindata[[v]])]
  levels_train <- sort(unique(observed))
  
  if (!length(levels_train)) {
    stop("训练集分类变量 ", v, " 没有可用观测值。")
  }
  
  counts <- table(factor(observed, levels = levels_train))
  fill_value <- levels_train[which.max(counts)]
  
  # 未见类别不属于缺失值，不能静默转成NA后插补。
  unknown_levels <- setdiff(
    unique(valdata[[v]][!is.na(valdata[[v]])]),
    levels_train
  )
  if (length(unknown_levels)) {
    stop(
      "验证集变量 ", v, " 出现训练集未见类别：",
      paste(unknown_levels, collapse = ", "),
      "。请核查编码或预先规定类别合并方案。"
    )
  }
  
  imputation_rules$categorical[[v]] <- fill_value
  imputation_rules$category_levels[[v]] <- levels_train
  
  traindata[[v]][is.na(traindata[[v]])] <- fill_value
  valdata[[v]][is.na(valdata[[v]])] <- fill_value
  
  traindata[[v]] <- factor(traindata[[v]], levels = levels_train)
  valdata[[v]] <- factor(valdata[[v]], levels = levels_train)
}

if (anyNA(traindata) || anyNA(valdata)) {
  stop("插补后仍有缺失值，请检查数据。")
}

############################################
######### 第五步：保存数据和插补规则 #########
############################################

write.csv(
  traindata,
  "traindata.csv",
  row.names = FALSE,
  fileEncoding = "GBK"
)

write.csv(
  valdata,
  "valdata.csv",
  row.names = FALSE,
  fileEncoding = "GBK"
)

saveRDS(
  list(
    split_seed = 201L,
    training_fraction = 0.7,
    missing_threshold = missing_threshold,
    predictor_vars = retained_vars,
    excluded_vars = excluded_vars,
    categorical_vars = retained_categorical,
    continuous_vars = retained_continuous,
    imputation_rules = imputation_rules,
    training_rows = inTrain,
    validation_rows = inValidation
  ),
  "训练集单次插补规则.rds"
)

capture.output(sessionInfo(), file = "软件及包版本.txt")

message(
  "处理完成。训练集：", nrow(traindata),
  "；内部验证集：", nrow(valdata),
  "；保留预测变量：", length(retained_vars), "。"
)