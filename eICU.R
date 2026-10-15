############################################
# 外部验证集单次插补
# 仅处理已保存随机森林模型使用的16个预测变量
# 使用MIMIC训练集保存的中位数/众数，不在eICU重新估计
############################################

######### 1. 设置路径 #########

work_dir <- "C:/Users/LENOVO/Desktop/mimic_revise_Boruta"

external_file <- file.path(work_dir, "origindata_eicu.csv")
rules_file <- file.path(work_dir, "训练集单次插补规则.rds")

# 如果原始CSV使用UTF-8编码，改为 "UTF-8-BOM"。
external_encoding <- "GBK"

# 每次运行创建新的输出目录，避免覆盖已有结果。
output_dir <- file.path(
  work_dir,
  paste0(
    "外部验证_16变量单次插补_",
    format(Sys.time(), "%Y%m%d_%H%M%S")
  )
)

if (!file.exists(external_file)) {
  stop("找不到外部原始数据：", external_file)
}
if (!file.exists(rules_file)) {
  stop("找不到训练集插补规则：", rules_file)
}
if (dir.exists(output_dir)) {
  stop("输出目录已存在，请稍后重试或修改 output_dir。")
}

######### 2. 指定最终模型变量 #########

# 此列表对应文件夹中已保存随机森林的16个变量。
# 如果重新训练后的模型特征发生变化，必须同步修改此列表。
final_predictors <- c(
  "mech_vent",
  "crrt_24h",
  "med_status",
  "age",
  "ucr",
  "charlson_score",
  "apsiii",
  "oasis",
  "sapsii",
  "sofa_score",
  "hr",
  "spo2",
  "rbc",
  "wbc",
  "platelets",
  "glucose"
)

# 最终模型的分类变量按名称确定，不按列的位置确定。
expected_categorical <- c(
  "mech_vent",
  "crrt_24h",
  "med_status"
)

expected_continuous <- setdiff(
  final_predictors,
  expected_categorical
)

######### 3. 读取并核查训练集规则 #########

rules <- readRDS(rules_file)

required_fields <- c(
  "predictor_vars",
  "categorical_vars",
  "continuous_vars",
  "imputation_rules"
)

if (!all(required_fields %in% names(rules))) {
  stop("训练集规则文件格式不正确，请使用前面训练集代码生成的RDS。")
}

missing_training_rules <- setdiff(
  final_predictors,
  rules$predictor_vars
)

if (length(missing_training_rules)) {
  stop(
    "训练集规则缺少最终模型变量：",
    paste(missing_training_rules, collapse = ", "),
    "。\n请核查训练集变量和最终模型特征。",
    "rrt与crrt_24h不能未经确认直接互换。"
  )
}

categorical_vars <- intersect(
  final_predictors,
  rules$categorical_vars
)

continuous_vars <- intersect(
  final_predictors,
  rules$continuous_vars
)

if (!setequal(categorical_vars, expected_categorical) ||
    !setequal(continuous_vars, expected_continuous)) {
  stop(
    "训练集规则中的16变量类型与已核查的模型类型不一致。",
    "\n请先在训练集代码中按变量名确定分类变量，",
    "重新生成训练集插补规则。"
  )
}

imputation_rules <- rules$imputation_rules

######### 4. 读取外部未插补数据 #########

external_raw <- read.csv(
  external_file,
  header = TRUE,
  fileEncoding = external_encoding,
  stringsAsFactors = FALSE,
  check.names = FALSE,
  na.strings = c("", "NA", "NaN", "NULL", "null", "N/A"),
  strip.white = TRUE
)

if (!nrow(external_raw)) {
  stop("外部数据没有观测记录。")
}
if (anyDuplicated(names(external_raw))) {
  stop("外部数据存在重复列名，请先核查。")
}

# 仅统一已确认定义和时间窗一致的CRRT列名。
# 不将rrt自动改名为crrt_24h。
if ("crrt_24" %in% names(external_raw)) {
  if ("crrt_24h" %in% names(external_raw)) {
    stop("同时存在crrt_24和crrt_24h，请先确认使用哪一列。")
  }
  names(external_raw)[names(external_raw) == "crrt_24"] <- "crrt_24h"
}

missing_model_columns <- setdiff(
  final_predictors,
  names(external_raw)
)

if (length(missing_model_columns)) {
  stop(
    "外部数据缺少最终模型实际使用的变量：",
    paste(missing_model_columns, collapse = ", "),
    "。\n请补充提取，或在训练集重新开发使用共同变量的模型。"
  )
}

# 不使用的候选变量无需存在于外部数据，也不参与插补。
unused_candidates <- setdiff(
  rules$predictor_vars,
  final_predictors
)

message("本次只处理最终模型的16个预测变量。")

if (length(unused_candidates)) {
  message(
    "不参与本次插补的训练候选变量：",
    paste(unused_candidates, collapse = ", ")
  )
}

######### 5. 检查实际结局 #########

# 请事先确认Outcome与训练集使用相同的结局定义。
if (!"Outcome" %in% names(external_raw)) {
  stop("外部验证数据缺少Outcome列。")
}

outcome <- suppressWarnings(
  as.numeric(as.character(external_raw$Outcome))
)

if (anyNA(outcome) || any(!outcome %in% c(0, 1))) {
  stop("外部Outcome必须完整且编码为0/1，结局不进行插补。")
}
if (length(unique(outcome)) != 2L) {
  stop("外部Outcome必须同时包含0和1，才能计算AUC等指标。")
}

external_raw$Outcome <- factor(outcome, levels = c(0, 1))

######### 6. 整理连续变量 #########

for (v in continuous_vars) {
  original <- external_raw[[v]]
  
  numeric_value <- suppressWarnings(
    as.numeric(as.character(original))
  )
  
  if (any(!is.na(original) & is.na(numeric_value))) {
    stop(
      "外部连续变量 ", v,
      " 存在非数值内容，请检查编码。"
    )
  }
  
  if (any(!is.na(numeric_value) & !is.finite(numeric_value))) {
    stop("外部连续变量 ", v, " 存在无穷值。")
  }
  
  external_raw[[v]] <- numeric_value
}

######### 7. 整理分类变量 #########

allowed_codes <- list(
  mech_vent = c("0", "1"),
  crrt_24h = c("0", "1"),
  med_status = c("0", "1", "2")
)

for (v in categorical_vars) {
  values <- trimws(as.character(external_raw[[v]]))
  values[!is.na(values) & values == ""] <- NA_character_
  
  observed <- unique(values[!is.na(values)])
  
  if (any(!observed %in% allowed_codes[[v]])) {
    stop(
      "分类变量 ", v, " 编码不符合要求。",
      "\n允许的编码：",
      paste(allowed_codes[[v]], collapse = ", ")
    )
  }
  
  levels_train <- imputation_rules$category_levels[[v]]
  
  if (is.null(levels_train) || !length(levels_train) ||
      anyNA(levels_train)) {
    stop("训练集规则缺少变量 ", v, " 的有效类别水平。")
  }
  
  unknown_levels <- setdiff(observed, levels_train)
  
  if (length(unknown_levels)) {
    stop(
      "外部分类变量 ", v, " 出现训练集未见类别：",
      paste(unknown_levels, collapse = ", "),
      "。请先核查编码及类别映射。"
    )
  }
  
  external_raw[[v]] <- values
}

######### 8. 统计插补前缺失情况 #########

missing_n <- vapply(
  external_raw[final_predictors],
  function(x) sum(is.na(x)),
  integer(1)
)

missing_ratio <- missing_n / nrow(external_raw)

missing_report <- data.frame(
  Dataset = "External validation",
  Variable = final_predictors,
  Type = ifelse(
    final_predictors %in% categorical_vars,
    "Categorical",
    "Continuous"
  ),
  N = nrow(external_raw),
  Missing_N = unname(missing_n),
  Missing_Percent = 100 * unname(missing_ratio),
  row.names = NULL
)

print(missing_report)

all_missing_vars <- final_predictors[
  missing_n == nrow(external_raw)
]

if (length(all_missing_vars)) {
  stop(
    "以下最终模型变量整列缺失：",
    paste(all_missing_vars, collapse = ", "),
    "。请先核查提取结果，不能静默整列插补。"
  )
}

high_missing_vars <- final_predictors[missing_ratio > 0.20]

if (length(high_missing_vars)) {
  warning(
    "以下最终模型变量在外部队列缺失超过20%：",
    paste(high_missing_vars, collapse = ", "),
    "。仍保留模型要求的变量，应报告并评估插补影响。",
    call. = FALSE
  )
}

missing_by_row <- rowSums(
  is.na(external_raw[final_predictors])
)

######### 9. 应用训练集中位数和众数 #########

testdata <- external_raw[c("Outcome", final_predictors)]

applied_rules <- vector("list", length(final_predictors))
names(applied_rules) <- final_predictors

# 连续变量使用MIMIC训练集中位数。
for (v in continuous_vars) {
  fill_value <- imputation_rules$continuous[[v]]
  
  if (!is.numeric(fill_value) ||
      length(fill_value) != 1L ||
      !is.finite(fill_value)) {
    stop("训练集变量 ", v, " 的中位数插补规则无效。")
  }
  
  testdata[[v]][is.na(testdata[[v]])] <- fill_value
  
  applied_rules[[v]] <- data.frame(
    Variable = v,
    Type = "Continuous",
    Method = "Training median",
    Fill_Value = as.character(fill_value),
    Imputed_N = unname(missing_n[v]),
    stringsAsFactors = FALSE
  )
}

# 分类变量使用MIMIC训练集众数和类别水平。
for (v in categorical_vars) {
  fill_value <- imputation_rules$categorical[[v]]
  levels_train <- imputation_rules$category_levels[[v]]
  
  if (length(fill_value) != 1L ||
      is.na(fill_value) ||
      !fill_value %in% levels_train) {
    stop("训练集变量 ", v, " 的众数插补规则无效。")
  }
  
  testdata[[v]][is.na(testdata[[v]])] <- fill_value
  
  testdata[[v]] <- factor(
    testdata[[v]],
    levels = levels_train
  )
  
  applied_rules[[v]] <- data.frame(
    Variable = v,
    Type = "Categorical",
    Method = "Training mode",
    Fill_Value = as.character(fill_value),
    Imputed_N = unname(missing_n[v]),
    stringsAsFactors = FALSE
  )
}

if (anyNA(testdata)) {
  stop("外部数据插补后仍存在缺失值，请核查。")
}

######### 10. 保存外部验证数据 #########

dir.create(
  output_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

write.csv(
  testdata,
  file.path(output_dir, "testdata.csv"),
  row.names = FALSE,
  fileEncoding = "GBK"
)

# RDS保留因子类型及训练集类别水平。
saveRDS(
  testdata,
  file.path(output_dir, "testdata.rds")
)

write.csv(
  missing_report,
  file.path(output_dir, "外部验证16变量缺失比例_插补前.csv"),
  row.names = FALSE,
  fileEncoding = "GBK"
)

write.csv(
  do.call(rbind, applied_rules[final_predictors]),
  file.path(output_dir, "外部验证使用的训练集插补规则.csv"),
  row.names = FALSE,
  fileEncoding = "GBK"
)

# 保存行对应关系，不改变原始患者顺序。
row_record <- data.frame(
  Original_Row = seq_len(nrow(external_raw)),
  Missing_Predictor_N = missing_by_row
)

id_names <- intersect(
  c(
    "subject_id", "hadm_id", "stay_id",
    "patientunitstayid", "hospital_stay_id",
    "hospitalid", "uniquepid"
  ),
  names(external_raw)
)

if (length(id_names)) {
  row_record <- cbind(
    row_record,
    external_raw[id_names]
  )
}

write.csv(
  row_record,
  file.path(output_dir, "外部验证行对应记录.csv"),
  row.names = FALSE,
  fileEncoding = "GBK"
)

saveRDS(
  list(
    external_source = normalizePath(
      external_file, winslash = "/"
    ),
    training_rules_source = normalizePath(
      rules_file, winslash = "/"
    ),
    final_predictors = final_predictors,
    categorical_vars = categorical_vars,
    continuous_vars = continuous_vars,
    applied_rules = applied_rules,
    missing_report = missing_report
  ),
  file.path(output_dir, "外部验证处理记录.rds")
)

capture.output(
  sessionInfo(),
  file = file.path(output_dir, "软件及包版本.txt")
)

message(
  "\n外部验证插补完成。",
  "\n患者数：", nrow(testdata),
  "\n预测变量数：", length(final_predictors),
  "\n插补前存在预测变量缺失的患者数：",
  sum(missing_by_row > 0),
  "\n插补后缺失值总数：", sum(is.na(testdata)),
  "\n结果目录：", output_dir
)