suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
})

die <- function(...) stop(paste0(...), call. = FALSE)
# ==========================
# 0. 读取参数
# ==========================
args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NULL) {
  i <- match(paste0("--", flag), args)
  if (is.na(i)) return(default)
  if (i == length(args)) die("Missing value for --", flag)
  args[i + 1]
}

count_fp   <- get_arg("counts")              # 单对比 DEG 结果文件
fpkm_fp <- get_arg("fpkm")
out <- get_arg("out","merged_FPKM_count.csv")

if (is.null(count_fp) || is.null(fpkm_fp)) die("Required: --counts --fpkm")
if (!file.exists(count_fp)) die("counts file not found: ", count_fp)
if (!file.exists(fpkm_fp)) die("FPKM file not found: ", fpkm_fp)

counts <- read.csv(count_fp, stringsAsFactors = FALSE)
fpkm   <- read.csv(fpkm_fp, stringsAsFactors = FALSE)
# 统一counts表的gene_id格式
old_ids <- counts$gene_id

new_ids <- ifelse(
  grepl("\\|", old_ids),
  old_ids,
  {
    left <- old_ids                               # 左边保留原样
    right <- sub("^gene-", "", old_ids)           # 右边去掉 gene- 前缀（如果有）
    paste0(left, "|", right)
  }
)

# 冲突检查：转换后是否出现重复主键
dup <- new_ids[duplicated(new_ids)]
if (length(dup) > 0) {
  cat("警告：转换后出现重复 gene_id，示例：\n")
  print(head(dup, 20))
  stop("转换后主键重复，请检查原始 counts 中是否有重复或命名不一致。")
}

# 保留原始 id 便于追溯
counts$gene_id_original <- old_ids
counts$gene_id <- new_ids

# counts 的 gene_key 是否唯一
stopifnot(!any(duplicated(counts$gene_id)))
# FPKM 的 gene_key 是否唯一
stopifnot(!any(duplicated(fpkm$gene_key)))
# 两者是否一一对应
stopifnot(setequal(counts$gene_id, fpkm$gene_key))
# 合并fpkm和couints
merged <- counts %>%
  left_join(fpkm, by = c("gene_id" = "gene_key"))

sum(is.na(merged[[grep("_FPKM$", colnames(merged))[1]]]))

fpkm_col <- grep("_FPKM$", colnames(merged), value = TRUE)[1]
# 找出在 final 里 FPKM 为 NA 的 gene_id
na_ids <- merged$gene_id[is.na(merged[[fpkm_col]])]

fpkm %>%
  filter(gene_key %in% na_ids) %>%
  select(gene_key, all_of(fpkm_col)) %>%
  head(32)

# 保存结果
write.csv(
  merged,
  file = out,
  row.names = FALSE
)



