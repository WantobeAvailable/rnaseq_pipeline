# PCA分析（FPKM）
# 屏蔽 package attach 时的“startup message”
suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
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
meta_fp  <- get_arg("meta")
fpkm_fp  <- get_arg("fpkm")
# 可选：高变基因数
top_n <- as.integer(get_arg("top_n", "5000"))
# 输出
out_png    <- get_arg("out_png", "PCA_batch_sd.png")
out_scores <- get_arg("out_scores", "PCA_scores_corrected_sd.csv")

# 必要参数检查
if (is.null(meta_fp) || is.null(fpkm_fp))die("Required: --meta --fpkm")
if (!file.exists(meta_fp)) die("Metadata file not found: ", meta_fp)
if (!file.exists(fpkm_fp)) die("FPKM file not found: ", fpkm_fp)

# ===============================
# 1. 读取数据
# ===============================
message("[1/6] Read input ...")
metadata <- read.csv(meta_fp, row.names = 1, check.names = FALSE)
fpkm_mat     <- read.csv(fpkm_fp, row.names = 1, check.names = FALSE)
# 保证 FPKM 列顺序与 metadata 行顺序一致
colnames(fpkm_mat) <- sub("_FPKM$", "", colnames(fpkm_mat))
fpkm_mat <- fpkm_mat[, rownames(metadata)]


# ===============================
# 2. 数据处理
# ===============================
message("[2/6] Preprocess expression matrix ...")

# 防御式转 numeric（避免读入成字符）
fpkm_num <- as.matrix(fpkm_mat)
mode(fpkm_num) <- "numeric"

# 筛选高变异基因,例如取前 5000 个
gene_sd <- apply(fpkm_num, 1, sd, na.rm = TRUE)
top_genes <- names(sort(gene_sd, decreasing = TRUE))[1:top_n]
fpkm_top <- fpkm_num[top_genes, ]

#  每个基因做中心化/标准化（Z-score）
fpkm_scaled <- t(scale(t(fpkm_top), center=TRUE, scale=TRUE))
# ===============================
# 3. PCA
# ===============================
message("[3/6] Preprocess PCA ...")
#  PCA（这里 scale.=FALSE，因为已经标准化过了）
pca_res <- prcomp(t(fpkm_scaled), scale.=FALSE)

# ===============================
# 4. 准备绘图数据
# ===============================
message("[4/6] Prepare drawing data ...")
# 确保 metadata 有一列 sample 用于 merge
metadata$sample <- rownames(metadata)
pca_df <- data.frame(
  sample = rownames(pca_res$x),
  PC1 = pca_res$x[,1],
  PC2 = pca_res$x[,2]
)
pca_df <- merge(pca_df, metadata, by="sample")

normalize_pc <- function(x, min_val=-0.3, max_val=0.6){
  x_scaled <- (x - min(x)) / (max(x) - min(x))  # 0~1
  x_scaled <- x_scaled * (max_val - min_val) + min_val
  return(x_scaled)
}

pca_df$PC1_norm <- normalize_pc(pca_df$PC1)
pca_df$PC2_norm <- normalize_pc(pca_df$PC2)
# ===============================
# 5. 绘制 PCA 图
# ===============================
message("[5/6] Drawing PCA ...")
ggplot(pca_df, aes(x=PC1_norm, y=PC2_norm, color=Group, shape=Time)) +
  geom_point(size=4) +
  theme_bw() +
  labs(
    x=paste0("PC1 (", round(summary(pca_res)$importance[2,1]*100,1), "%)"),
    y=paste0("PC2 (", round(summary(pca_res)$importance[2,2]*100,1), "%)"),
    title="PCA of gut transcriptome"
  ) +
  scale_color_manual(values=c("WT"="red","MU"="blue","SMU"="green")) +
  scale_shape_manual(values=c("3M"=16, "6M"=17)) +
  coord_cartesian(xlim=c(-0.3,0.6), ylim=c(-0.3,0.6)) +
  theme(
    plot.title = element_text(hjust = 0.5, size=16),
    axis.title = element_text(size=14),
    axis.text = element_text(size=12)
  )

# ===============================
# 6. 输出 PCA 坐标（可选）
# ===============================
message("[6/6] Saving results ...")
ggsave(
  filename = out_png,  # 文件名
  plot = last_plot(),         # 当前最后一张 ggplot
  width = 6,                  # 宽度（英寸）
  height = 5,                 # 高度（英寸）
  dpi = 300                   # 分辨率，300 dpi 用于论文
)
write.csv(pca_res$x, out_scores, row.names = TRUE)
