library(DESeq2)
library(dplyr)
# ================================DEG分析=======================================
# ===============================
# 1. 读取原始数据
# ===============================
count_mat <- read.csv("gene_count_matrix.csv", row.names = 1, check.names = FALSE)
metadata <- read.csv("rawdata/metadata.csv", row.names = 1, check.names = FALSE)
# 确保 counts matrix 列名与 metadata 行名一致
count_mat <- count_mat[, rownames(metadata)]
all(colnames(count_mat) == rownames(metadata))  # TRUE

# ===============================
# 2. 取子集样本
# ===============================
# 3月龄的MU_VS_WT
meta_3M <- metadata[
  metadata$age_month == 3 &
    metadata$health_status == "healthy",
]
meta_3M$genotype <- factor(
     meta_3M$genotype,
     levels = c("WT", "MU")
)
# 6月龄的MU_VS_WT
meta_6M_MU <- metadata[
     metadata$age_month == 6 &
        metadata$health_status == "healthy",
]
meta_6M_MU$genotype <- factor(
     meta_6M_MU$genotype,
     levels = c("WT", "MU")
)
# 6月龄的SMU_VS_WT
meta_6M_SMU <- metadata[
     metadata$age_month == 6 &
         (
             metadata$genotype == "WT" |
                 metadata$health_status == "sick"
         ),
]
# 重新定义比较变量
meta_6M_SMU$group <- ifelse(
     meta_6M_SMU$health_status == "sick",
     "SMU", "WT"
)
meta_6M_SMU$group <- factor(meta_6M_SMU$group, levels = c("WT", "SMU"))

# ===============================
# 3. 构建 DESeq2 对象并计算
# ===============================
# 3月龄的MU_VS_WT
dds_3M <- DESeqDataSetFromMatrix(
  countData = count_mat[, rownames(meta_3M)],
  colData   = meta_3M,
  design    = ~ genotype
)
dds_3M <- DESeq(dds_3M)
# 6月龄的MU_VS_WT
dds_6M_MU <- DESeqDataSetFromMatrix(
  countData = count_mat[, rownames(meta_6M_MU)],
  colData   = meta_6M_MU,
  design    = ~ genotype
)
dds_6M_MU <- DESeq(dds_6M_MU)
# 6月龄的SMU_VS_WT
dds_6M_SMU <- DESeqDataSetFromMatrix(
  countData = count_mat[, rownames(meta_6M_SMU)],
  colData   = meta_6M_SMU,
  design    = ~ group
)
dds_6M_SMU <- DESeq(dds_6M_SMU)
# ===============================
# 4. 取结果
# ===============================
res_3M <- results(dds_3M,
                  contrast = c("genotype", "MU", "WT"))
res_6M_MU <- results(dds_6M_MU,
                     contrast = c("genotype", "MU", "WT"))
res_6M_SMU <- results(dds_6M_SMU,
                      contrast = c("group", "SMU", "WT"))
saveRDS(res_3M, "res_3M.rds")
saveRDS(res_6M_MU, "res_6M_MU.rds")
saveRDS(res_6M_SMU, "res_6M_SMU.rds")
write.csv(as.data.frame(res_3M), "res_3M.csv", row.names = TRUE)
write.csv(as.data.frame(res_6M_MU), "res_6M_MU.csv", row.names = TRUE)
write.csv(as.data.frame(res_6M_SMU), "res_6M_SMU.csv", row.names = TRUE)
# ===============================
# 5. 合并结果
# ===============================
# 统一成 data.frame 并加 gene_id
# 3M
res_3M_df <- as.data.frame(res_3M)
res_3M_df$gene_id <- rownames(res_3M_df)
res_3M_df <- res_3M_df[, c("gene_id", "baseMean", "log2FoldChange", "pvalue")]

# 6M MU
res_6M_MU_df <- as.data.frame(res_6M_MU)
res_6M_MU_df$gene_id <- rownames(res_6M_MU_df)
res_6M_MU_df <- res_6M_MU_df[, c("gene_id", "baseMean", "log2FoldChange", "pvalue")]

# 6M SMU
res_6M_SMU_df <- as.data.frame(res_6M_SMU)
res_6M_SMU_df$gene_id <- rownames(res_6M_SMU_df)
res_6M_SMU_df <- res_6M_SMU_df[, c("gene_id", "baseMean", "log2FoldChange", "pvalue")]
# 统一列名（方便区分每个比较）
colnames(res_3M_df) <- c(
  "gene_id",
  "3M_MU_VS_WT_baseMean",
  "3M_MU_VS_WT_log2FoldChange",
  "3M_MU_VS_WT_pvalue"
)

colnames(res_6M_MU_df) <- c(
  "gene_id",
  "6M_MU_VS_WT_baseMean",
  "6M_MU_VS_WT_log2FoldChange",
  "6M_MU_VS_WT_pvalue"
)

colnames(res_6M_SMU_df) <- c(
  "gene_id",
  "6M_SMU_VS_WT_baseMean",
  "6M_SMU_VS_WT_log2FoldChange",
  "6M_SMU_VS_WT_pvalue"
)
# 按 gene_id 合并三张表，全外连接，确保所有基因都出现，如果某个比较没有该基因则填 NA
res_all <- res_3M_df %>%
  full_join(res_6M_MU_df, by = "gene_id") %>%
  full_join(res_6M_SMU_df, by = "gene_id")

write.csv(res_all, "all_DEG_results.csv", row.names = FALSE)


