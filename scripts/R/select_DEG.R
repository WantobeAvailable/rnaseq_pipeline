# ==========================
# 1. 加载必要包
# ==========================
library(data.table)

# ==========================
# 2. 读取 DEG 结果
# ==========================
deg_file <- "all_DEG_results.csv"
deg <- fread(deg_file, check.names = FALSE)  # 保留原始列名

# 查看列名确认
colnames(deg)

# ==========================
# 3. 定义筛选函数
# ==========================
# 输入：data.table, log2FC列名, pvalue列名, LFC阈值, p值阈值
# 输出：筛选后的 DEG data.table
filter_DEG <- function(dt, log2FC_col, pval_col, lfc_cut=1.5, p_cut=0.05) {
  dt_filtered <- dt[
    !is.na(get(pval_col)) &
      abs(get(log2FC_col)) > lfc_cut &
      get(pval_col) < p_cut
  ]
  return(dt_filtered)
}

# ==========================
# 4. 筛选各组 DEG
# ==========================
deg_3M <- filter_DEG(deg, "3M_MU_VS_WT_log2FoldChange", "3M_MU_VS_WT_pvalue")
deg_6M <- filter_DEG(deg, "6M_MU_VS_WT_log2FoldChange", "6M_MU_VS_WT_pvalue")
deg_6M_SMU <- filter_DEG(deg, "6M_SMU_VS_WT_log2FoldChange", "6M_SMU_VS_WT_pvalue")

# ==========================
# 5. 上调 / 下调基因
# ==========================
get_up_down <- function(dt, log2FC_col) {
  up <- dt[get(log2FC_col) > 1.5]
  down <- dt[get(log2FC_col) < -1.5]
  list(up = up, down = down)
}

deg_3M_ud <- get_up_down(deg_3M, "3M_MU_VS_WT_log2FoldChange")
deg_6M_ud <- get_up_down(deg_6M, "6M_MU_VS_WT_log2FoldChange")
deg_6M_SMU_ud <- get_up_down(deg_6M_SMU, "6M_SMU_VS_WT_log2FoldChange")

# ==========================
# 6. 输出 DEG 表
# ==========================
fwrite(deg_3M, "DEG_3M_MU_vs_WT_all.csv")
fwrite(deg_3M_ud$up, "DEG_3M_MU_vs_WT_up.csv")
fwrite(deg_3M_ud$down, "DEG_3M_MU_vs_WT_down.csv")

fwrite(deg_6M, "DEG_6M_MU_vs_WT_all.csv")
fwrite(deg_6M_ud$up, "DEG_6M_MU_vs_WT_up.csv")
fwrite(deg_6M_ud$down, "DEG_6M_MU_vs_WT_down.csv")

fwrite(deg_6M_SMU, "DEG_6M_SMU_vs_WT_all.csv")
fwrite(deg_6M_SMU_ud$up, "DEG_6M_SMU_vs_WT_up.csv")
fwrite(deg_6M_SMU_ud$down, "DEG_6M_SMU_vs_WT_down.csv")

# ==========================
# 7. 输出 DEG 数量统计（可选）
# ==========================
cat("3M MU vs WT: ", nrow(deg_3M), "DEGs\n")
cat("   Up: ", nrow(deg_3M_ud$up), " Down: ", nrow(deg_3M_ud$down), "\n")
cat("6M MU vs WT: ", nrow(deg_6M), "DEGs\n")
cat("   Up: ", nrow(deg_6M_ud$up), " Down: ", nrow(deg_6M_ud$down), "\n")
cat("6M SMU vs WT: ", nrow(deg_6M_SMU), "DEGs\n")
cat("   Up: ", nrow(deg_6M_SMU_ud$up), " Down: ", nrow(deg_6M_SMU_ud$down), "\n")
