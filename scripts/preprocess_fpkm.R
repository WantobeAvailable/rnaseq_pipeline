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

meta_fp <- get_arg("meta")
fpkm_fp <- get_arg("fpkm")
out_numeric <- get_arg("out_numeric", "fpkm.preprocessed.numeric.csv")
out_with_anno <- get_arg("out_with_anno", "fpkm.preprocessed.with_anno.csv")

if (is.null(meta_fp) || is.null(fpkm_fp)) die("Required: --meta --fpkm")
if (!file.exists(meta_fp)) die("Metadata file not found: ", meta_fp)
if (!file.exists(fpkm_fp)) die("FPKM file not found: ", fpkm_fp)

# ===============================
# 1. 读取数据
# ===============================
message("[1/4] Read input ...")
metadata <- read.csv(meta_fp, row.names = 1, check.names = FALSE)
fpkm_all <- read.csv(fpkm_fp, row.names = 1, check.names = FALSE)

# ===============================
# 2. 识别表达列 + 列名映射（SRRxxx_FPKM -> SRRxxx）
# ===============================
message("[2/4] Align samples ...")
fpkm_cols <- colnames(fpkm_all)
mapped_ids <- sub("_FPKM.*$", "", fpkm_cols)

meta_ids <- rownames(metadata)

common_ids <- intersect(mapped_ids, meta_ids)
if (length(common_ids) < 2) die("Too few common samples after mapping.")

fpkm_idx <- match(common_ids, mapped_ids)
meta_idx <- match(common_ids, meta_ids)

# 子集并对齐顺序
fpkm <- fpkm_all[, fpkm_idx, drop = FALSE]
metadata <- metadata[meta_idx, , drop = FALSE]

# 注释列（表达列之外的所有列）
anno_cols <- setdiff(colnames(fpkm_all), colnames(fpkm))
anno_df <- fpkm_all[, anno_cols, drop = FALSE]

# ===============================
# 3. 数据处理（必做）
# ===============================
message("[3/4] Preprocess expression matrix ...")

fpkm_mat <- as.matrix(fpkm)
mode(fpkm_mat) <- "numeric"

# log2(FPKM+1)
fpkm_log <- log2(fpkm_mat + 1)

# 去掉含 NA 的基因
fpkm_log <- fpkm_log[complete.cases(fpkm_log), , drop = FALSE]

# 去掉 sd=0 的基因
sd_vec <- apply(fpkm_log, 1, sd)
fpkm_filtered <- fpkm_log[sd_vec > 0, , drop = FALSE]

# ===============================
# 4. 输出两个结果文件
# ===============================
message("[4/4] Write results ...")

# 1) 纯数值矩阵
colnames(fpkm_filtered) <- sub("_FPKM$", "", colnames(fpkm_filtered))
out_numeric_df <- data.frame(
  gene_id = rownames(fpkm_filtered),
  fpkm_filtered,
  check.names = FALSE,
  row.names = NULL
)
write.csv(out_numeric_df, file = out_numeric, quote = FALSE, row.names = FALSE)

# 2) 注释 + 数值（按过滤后的 gene_key 对齐注释行）
anno_df2 <- anno_df[rownames(fpkm_filtered), , drop = FALSE]
out_df <- cbind(anno_df2, fpkm_filtered)
out_with_anno_df <- data.frame(
  gene_id = rownames(out_df),
  out_df,
  check.names = FALSE,
  row.names = NULL
)
write.csv(out_with_anno_df, file = out_with_anno, quote = FALSE, row.names = FALSE)

message("Preprocessed numeric written to: ", out_numeric)
message("Preprocessed with-anno written to: ", out_with_anno)
