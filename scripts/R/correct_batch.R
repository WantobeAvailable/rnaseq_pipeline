#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(sva)
})

die <- function(...) stop(paste0(...), call. = FALSE)

# ===============================
# 0. 提取参数
# ===============================
args <- commandArgs(trailingOnly = TRUE)

get_arg <- function(flag, default = NULL) {
  i <- match(paste0("--", flag), args)
  if (is.na(i)) return(default)
  if (i == length(args)) die("Missing value for --", flag)
  args[i + 1]
}

meta_fp    <- get_arg("meta")
fpkm_fp    <- get_arg("fpkm")                 # 这里建议传 preprocess 的 numeric 输出
batch_col  <- get_arg("batch_col", "Batch")
design_str <- get_arg("design", NULL)
out        <- get_arg("out", "fpkm.combat.csv")

if (is.null(meta_fp) || is.null(fpkm_fp)) die("Required: --meta --fpkm")
if (!file.exists(meta_fp)) die("Metadata file not found: ", meta_fp)
if (!file.exists(fpkm_fp)) die("FPKM file not found: ", fpkm_fp)

# ===============================
# 1. 读取数据
# ===============================
message("[1/4] Read input ...")
metadata <- read.csv(meta_fp, row.names = 1, check.names = FALSE)
fpkm_mat <- read.csv(fpkm_fp, row.names = 1, check.names = FALSE)

# ===============================
# 2. 对齐样本
# ===============================
message("[2/4] Align samples ...")
fpkm_cols <- colnames(fpkm_mat)
mapped_ids <- sub("_FPKM.*$", "", fpkm_cols)

meta_ids <- rownames(metadata)

common_ids <- intersect(mapped_ids, meta_ids)
if (length(common_ids) < 2) die("Too few common samples after mapping.")

fpkm_idx <- match(common_ids, mapped_ids)
meta_idx <- match(common_ids, meta_ids)

fpkm_mat <- fpkm_mat[, fpkm_idx, drop = FALSE]
metadata <- metadata[meta_idx, , drop = FALSE]

# batch
if (!batch_col %in% colnames(metadata)) die("Batch column not found: ", batch_col)
batch <- metadata[[batch_col]]

# ===============================
# 3. 构建设计矩阵（可选）
# ===============================
message("[3/4] Prepare design matrix ...")
mod <- NULL
if (!is.null(design_str)) {
  vars <- all.vars(as.formula(paste0("~", design_str)))
  for (v in vars) {
    if (!v %in% colnames(metadata)) die("Design variable not found: ", v)
    metadata[[v]] <- factor(metadata[[v]])
  }
  mod <- model.matrix(as.formula(paste0("~", design_str)), data = metadata)
}

# ===============================
# 4. ComBat + 输出
# ===============================
message("[4/4] Running ComBat and writing results ...")

fpkm_num <- as.matrix(fpkm_mat)
mode(fpkm_num) <- "numeric"

fpkm_corrected <- ComBat(
  dat = fpkm_num,
  batch = batch,
  mod = mod,
  par.prior = TRUE,
  prior.plots = FALSE
)

write.csv(fpkm_corrected, file = out, quote = FALSE)
message("Batch-corrected matrix written to: ", out)

