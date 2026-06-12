#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(readr)
  library(ggplot2)
  library(dplyr)
  library(pheatmap)
})

die <- function(...) stop(paste0(...), call. = FALSE)

# ===============================
# 0. 参数提取
# ===============================
args <- commandArgs(trailingOnly = TRUE)

get_arg <- function(flag, default = NULL){
  i <- match(paste0("--", flag), args)
  if (is.na(i)) return(default)
  if (i == length(args)) die("Missing value for --", flag)
  args[i + 1]
}

fpkm_fp   <- get_arg("fpkm")
module_fp <- get_arg("module")
meta_fp   <- get_arg("meta")
out_pdf   <- get_arg("out", "final_heatmap.pdf")

# 可选：顺序参数（逗号分隔）
group_order_str  <- get_arg("group_order", NULL)
module_order_str <- get_arg("module_order", NULL)

if (is.null(fpkm_fp) || is.null(module_fp) || is.null(meta_fp)){
  die("Required: --fpkm --module --meta")
}

if (!file.exists(fpkm_fp)) die("FPKM file not found: ", fpkm_fp)
if (!file.exists(module_fp)) die("Module file not found: ", module_fp)
if (!file.exists(meta_fp)) die("Metadata file not found: ", meta_fp)

# ===============================
# 1. 读取数据
# ===============================
message("[1/5] Reading input files...")

fpkm     <- read.csv(fpkm_fp, stringsAsFactors = FALSE, check.names = FALSE)
module   <- read.csv(module_fp, stringsAsFactors = FALSE, check.names = FALSE)
metadata <- read.csv(meta_fp, stringsAsFactors = FALSE, check.names = FALSE)

if (!("Gene.Name" %in% colnames(fpkm))) {
  die("FPKM file missing required column: Gene.Name")
}
if (!all(c("DR_gene_symbol", "Type") %in% colnames(module))) {
  die("Module file missing required columns: DR_gene_symbol, Type")
}
if (!all(c("run_id", "Treat") %in% colnames(metadata))) {
  die("Metadata file missing required columns: run_id, Treat")
}


# ===============================
# 2. 基因名处理（保持你原逻辑）
# ===============================
fpkm$gene_symbol <- fpkm$Gene.Name

module$order_in_module <- ave(
  seq_len(nrow(module)),
  module$Type,
  FUN = seq_along
)

genes_use <- intersect(fpkm$gene_symbol, module$DR_gene_symbol)
fpkm_use <- fpkm[fpkm$gene_symbol %in% genes_use, ]

if (length(genes_use) == 0) {
  die("No overlapping genes between fpkm$Gene.Name and module$DR_gene_symbol")
}

# 注释列排除
anno_cols <- c("gene_symbol", "Gene.Name", "gene_key", "Gene.ID", "status")
sample_cols <- setdiff(colnames(fpkm_use), anno_cols)

# 防止空列名/NA列名导致索引报错
sample_cols <- sample_cols[!is.na(sample_cols) & nzchar(sample_cols)]
sample_cols <- intersect(sample_cols, colnames(fpkm_use))

if (length(sample_cols) == 0) {
  die("No candidate sample columns found after excluding annotation columns")
}

# 保留 numeric 表达列
sample_cols <- sample_cols[sapply(fpkm_use[, sample_cols, drop = FALSE], is.numeric)]

if (length(sample_cols) == 0) {
  die("No numeric sample columns found in FPKM matrix")
}

# symbol 合并取均值
fpkm_use <- fpkm_use %>%
  group_by(gene_symbol) %>%
  summarise(across(all_of(sample_cols), mean), .groups = "drop")

# 行注释
row_anno <- data.frame(
  Module = module$Type[match(fpkm_use$gene_symbol, module$DR_gene_symbol)],
  row.names = fpkm_use$gene_symbol,
  check.names = FALSE
)

# Module 顺序参数化
if (!is.null(module_order_str)){
  module_levels <- strsplit(module_order_str, ",")[[1]]
  row_anno$Module <- factor(row_anno$Module, levels = module_levels)
}

# ===============================
# 3. 构建表达矩阵（保持你原逻辑）
# ===============================
expr <- as.matrix(fpkm_use[, sample_cols])
rownames(expr) <- fpkm_use$gene_symbol

expr_log2 <- log2(expr + 1)
expr_scaled <- t(scale(t(expr_log2)))
expr_scaled[is.na(expr_scaled)] <- 0

# 去掉 _FPKM 后缀（你已经确定写死）
colnames(expr_scaled) <- sub("_FPKM$", "", colnames(expr_scaled))

# ===============================
# 4. 样本注释与排序（Group 顺序参数化）
# ===============================
metadata <- metadata[match(colnames(expr_scaled), metadata$run_id), ]

col_anno <- data.frame(
  Group = metadata$Treat,
  row.names = metadata$run_id,
  check.names = FALSE
)

# Group 顺序参数化
if (!is.null(group_order_str)){
  group_levels <- strsplit(group_order_str, ",")[[1]]
  metadata$Treat <- factor(metadata$Treat, levels = group_levels)
}

# 按 Group 排序
group_labels <- metadata$Treat[match(colnames(expr_scaled), metadata$run_id)]
group_counts <- table(group_labels[order(group_labels)])
col_gaps <- cumsum(group_counts)[-length(group_counts)]

col_order <- colnames(expr_scaled)[order(group_labels)]

# 行顺序（保持你原逻辑）
row_order_df <- data.frame(
  gene   = fpkm_use$gene_symbol,
  Module = row_anno$Module,
  order_in_module = module$order_in_module[
    match(fpkm_use$gene_symbol, module$DR_gene_symbol)
  ],
  stringsAsFactors = FALSE
)

row_order_df <- row_order_df[
  order(row_order_df$Module, row_order_df$order_in_module),
]

row_order <- row_order_df$gene

# ===============================
# 5. 绘图输出（完全保留你的绘图逻辑）
# ===============================
message("[5/5] Drawing heatmap...")

# 配色保持不变
n_half <- 50
neg_cols <- colorRampPalette(c("navy", "white"))(n_half)
pos_cols <- colorRampPalette(c("white", "#FFB347", "firebrick3"))(n_half)
heat_colors <- c(neg_cols, "white", pos_cols)

lim <- max(abs(expr_scaled), na.rm = TRUE)
heat_breaks <- seq(-lim, lim, length.out = length(heat_colors) + 1)

anno_colors <- list(
  Module = c(
    "Cell Cycle" = "#3498DB",
    "Digestion"  = "#E74C3C",
    "Immune"     = "#9B59B6"
  )
)

while (!is.null(dev.list())) dev.off()

grDevices::cairo_pdf(out_pdf, width = 10, height = 15, bg = "white")

pheatmap(expr_scaled[row_order, col_order],
         annotation_row = row_anno,
         annotation_names_row = TRUE,
         annotation_colors = anno_colors,
         fontsize = 10,
         show_colnames = FALSE,
         gaps_col = col_gaps,
         show_rownames = TRUE,
         fontsize_row = 7,
         cellheight = 8,
         cluster_rows = FALSE,
         cluster_cols = FALSE,
         annotation_col = NULL,
         annotation_legend = FALSE,
         color = heat_colors,
         breaks = heat_breaks,
         cellwidth = 12,
         fontsize_col = 11
)

dev.off()

message("Heatmap saved to: ", out_pdf)
