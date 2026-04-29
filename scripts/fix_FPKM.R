suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
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
# 提取参数
counts_fp <- get_arg("counts")
fpkm_fp   <- get_arg("fpkm")
# 输出
out_fix   <- get_arg("out_fix", "merged_FPKM_fixed.csv")
out_unfix <- get_arg("out_unfix", "FPKM_unfixed.csv")
# 必要参数检查
if (is.null(counts_fp) || is.null(fpkm_fp))die("Required: --counts --fpkm")
# ===============================
# 1. 根据counts表修复FPKM表
# ===============================
counts <- read.csv(counts_fp, row.names = 1, check.names = FALSE)

old_ids <- rownames(counts)

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

# 更新行名
rownames(counts) <- new_ids


# 读取 counts，构建“官方映射表”
meta <- data.frame(
  gene_key = rownames(counts),
  Gene.ID = sub("\\|.*$", "", rownames(counts)),
  Gene.Name = sub("^.*\\|", "", rownames(counts)),
  stringsAsFactors = FALSE
)
# 读取 FPKM 合并表（未处理重复版）
fpkm <- read.csv(fpkm_fp, stringsAsFactors = FALSE)
# 标记原始状态
fpkm$status <- "original"
# 找出 Gene.ID="." 的条目
fpkm_dot <- fpkm %>% filter(Gene.ID == ".")
fpkm_ok  <- fpkm %>% filter(Gene.ID != ".")
# 只保留唯一映射：Gene.Name -> Gene.ID
name_map_unique <- meta %>%
  group_by(Gene.Name) %>%
  reframe(
    mapped_Gene.ID = unique(Gene.ID),
    n = n_distinct(Gene.ID)
  ) %>%
  filter(n == 1) %>%
  select(Gene.Name, mapped_Gene.ID)
# 修复 Gene.ID="."
fpkm_dot_fix <- fpkm_dot %>%
  left_join(name_map_unique, by = "Gene.Name") %>%
  mutate(
    Gene.ID = ifelse(!is.na(mapped_Gene.ID), mapped_Gene.ID, Gene.ID),
    status = ifelse(!is.na(mapped_Gene.ID), "fixed_by_GeneName", "unfixed_dot")
  ) %>%
  select(-mapped_Gene.ID)
# 合并修复成功的 & 未修复的
fpkm_fixed <- bind_rows(fpkm_ok, fpkm_dot_fix)
# 构造最终 gene_key（与 counts 完全一致）
fpkm_fixed$gene_key <- paste(fpkm_fixed$Gene.ID, fpkm_fixed$Gene.Name, sep="|")
# gene-level 汇总（这是唯一安全的聚合点）
fpkm_cols <- grep("FPKM", names(fpkm_fixed), value = TRUE)

fpkm_gene <- fpkm_fixed %>%
  group_by(gene_key) %>%
  summarise(
    across(all_of(fpkm_cols), ~sum(.x, na.rm = TRUE)),
    status = paste(unique(status), collapse = ";"),
    .groups = "drop"
  )
# 与 counts 对齐（主表驱动）
final <- meta %>%
  left_join(fpkm_gene, by = "gene_key")
# 输出统计报告
cat("===== Gene.ID 修复统计 =====\n")
print(table(fpkm_fixed$status))

cat("\n===== 最终缺失 FPKM 的基因数 =====\n")
print(sum(is.na(final[, grep("FPKM", colnames(final))[1]])))

# 记录many to many 基因
counts_ids <- rownames(counts)

counts_map <- data.frame(
  counts_gene_id = counts_ids,
  counts_Gene.Name = ifelse(
    grepl("\\|", counts_ids),
    sub("^.*\\|", "", counts_ids),
    sub("^gene-", "", counts_ids)
  ),
  stringsAsFactors = FALSE
) %>%
  group_by(counts_Gene.Name) %>%
  summarise(
    candidate_gene_ids = paste(unique(counts_gene_id), collapse = ";"),
    n_candidates = n_distinct(counts_gene_id),
    .groups = "drop"
  )
unfixed_tbl_annot <- fpkm_fixed %>%
  filter(status == "unfixed_dot") %>%
  left_join(counts_map, by = c("Gene.Name" = "counts_Gene.Name"))

# 输出文件
write.csv(final, out_fix, row.names = FALSE)
write.csv(unfixed_tbl_annot, out_unfix, row.names = FALSE)
