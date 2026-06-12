#!/usr/bin/env Rscript

suppressPackageStartupMessages({
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

fpkm_fp    <- get_arg("fpkm")
meta_fp    <- get_arg("meta")
out_prefix <- get_arg("out", "heatmap")

# Mode 1: variance
n_var          <- as.integer(get_arg("n_var", "200"))

# Mode 2: DEG
deg_up_fp   <- get_arg("deg_up",   NULL)
deg_down_fp <- get_arg("deg_down", NULL)
n_deg       <- as.integer(get_arg("n_deg", "100"))
deg_groups_str <- get_arg("deg_groups", NULL)

# Mode 3: module
module_fp        <- get_arg("module", NULL)
module_order_str <- get_arg("module_order", NULL)

# 公共
group_order_str  <- get_arg("group_order", NULL)

if (is.null(fpkm_fp) || is.null(meta_fp)){
  die("Required: --fpkm --meta")
}
if (!file.exists(fpkm_fp)) die("FPKM file not found: ", fpkm_fp)
if (!file.exists(meta_fp)) die("Metadata file not found: ", meta_fp)

# ===============================
# 1. 读取公共数据
# ===============================
message("[1/4] Reading input files...")

fpkm     <- read.csv(fpkm_fp, row.names = 1, stringsAsFactors = FALSE, check.names = FALSE)
metadata <- read.csv(meta_fp, stringsAsFactors = FALSE, check.names = FALSE)

if (!all(c("run_id", "Treat") %in% colnames(metadata))) {
  die("Metadata file missing required columns: run_id, Treat")
}

# ===============================
# 2. 构建基础 FPKM 矩阵
# ===============================
message("[2/4] Building FPKM matrix...")

if ("Gene.Name" %in% colnames(fpkm)) {
  fpkm$gene_symbol <- as.character(fpkm$Gene.Name)
} else {
  rk <- rownames(fpkm)
  fpkm$gene_symbol <- ifelse(grepl("\\|", rk), sub("^.*\\|", "", rk), rk)
}

anno_cols   <- c("gene_symbol", "Gene.Name", "gene_key", "Gene.ID", "status")
sample_cols <- setdiff(colnames(fpkm), anno_cols)
sample_cols <- sample_cols[!is.na(sample_cols) & nzchar(sample_cols)]
sample_cols <- intersect(sample_cols, colnames(fpkm))
sample_cols <- sample_cols[sapply(fpkm[, sample_cols, drop = FALSE], is.numeric)]

if (length(sample_cols) == 0) die("No numeric sample columns found in FPKM matrix")

# 同一 symbol 取均值去重
fpkm_all <- fpkm %>%
  group_by(gene_symbol) %>%
  summarise(across(all_of(sample_cols), mean), .groups = "drop")

fpkm_mat <- as.matrix(fpkm_all[, sample_cols])
rownames(fpkm_mat) <- fpkm_all$gene_symbol

# 保留一份按 gene_id 去重的矩阵（供 Mode 2 使用，避免 symbol 重复问题）
fpkm$gene_id <- rownames(fpkm)
fpkm_all_id <- fpkm %>%
  group_by(gene_id) %>%
  summarise(across(all_of(sample_cols), mean), .groups = "drop")

fpkm_mat_id <- as.matrix(fpkm_all_id[, sample_cols])
rownames(fpkm_mat_id) <- fpkm_all_id$gene_id

# 去掉 _FPKM 后缀
colnames(fpkm_mat) <- sub("_FPKM$", "", colnames(fpkm_mat))
colnames(fpkm_mat_id) <- sub("_FPKM$", "", colnames(fpkm_mat_id))

# ===============================
# 3. 公共：样本排序 & gap 计算
# ===============================
message("[3/4] Computing sample order...")

matched_idx <- match(colnames(fpkm_mat), metadata$run_id)
valid <- !is.na(matched_idx)
if (!all(valid)) {
  warning("Some FPKM columns not found in metadata and will be dropped: ",
          paste(colnames(fpkm_mat)[!valid], collapse = ", "))
}
fpkm_mat         <- fpkm_mat[, valid, drop = FALSE]
fpkm_mat_id      <- fpkm_mat_id[, valid, drop = FALSE]
metadata_ordered <- metadata[matched_idx[valid], , drop = FALSE]

if (!is.null(group_order_str)){
  group_levels <- strsplit(group_order_str, ",")[[1]]
  metadata_ordered$Treat <- factor(metadata_ordered$Treat, levels = group_levels)
} else {
  metadata_ordered$Treat <- factor(metadata_ordered$Treat)
}

group_labels <- metadata_ordered$Treat
col_order    <- colnames(fpkm_mat)[order(group_labels)]
group_counts <- table(group_labels[order(group_labels)])
group_counts <- group_counts[group_counts > 0]
col_gaps     <- if (length(group_counts) > 1) cumsum(group_counts)[-length(group_counts)] else NULL

# 顶部样本分组注释（供 Mode 1/2 使用）
sample_group_map <- setNames(as.character(metadata_ordered$Treat), colnames(fpkm_mat))
group_levels_all <- levels(metadata_ordered$Treat)
group_palette <- grDevices::hcl.colors(max(length(group_levels_all), 3), palette = "Dark 3")
group_colors <- setNames(group_palette[seq_along(group_levels_all)], group_levels_all)
col_anno_from_cols <- function(cols) {
  grp <- sample_group_map[cols]
  data.frame(
    Group = factor(grp, levels = group_levels_all),
    row.names = cols,
    check.names = FALSE
  )
}

# ===============================
# 公共工具函数
# ===============================

# z-score 标准化（输入应为预处理后的表达矩阵）
scale_expr <- function(mat) {
  scaled <- t(scale(t(mat)))
  scaled[is.na(scaled)] <- 0
  scaled
}

# 组内样本聚类（保证同组样本仍然连在一起）
order_cols_within_group <- function(expr_scaled, sample_names, group_factor) {
  out <- character(0)
  for (g in levels(group_factor)) {
    idx <- which(group_factor == g)
    if (length(idx) == 0) next
    if (length(idx) == 1) {
      out <- c(out, sample_names[idx])
      next
    }
    sub_mat <- t(expr_scaled[, idx, drop = FALSE])
    ord_local <- tryCatch(hclust(dist(sub_mat))$order, error = function(e) seq_along(idx))
    out <- c(out, sample_names[idx][ord_local])
  }
  idx_na <- which(is.na(group_factor))
  if (length(idx_na) > 0) out <- c(out, sample_names[idx_na])
  out
}

# 模块内基因聚类（保证同模块仍然连在一起）
order_rows_within_module <- function(expr_scaled, module_factor) {
  out <- character(0)
  for (m in levels(module_factor)) {
    idx <- which(module_factor == m)
    if (length(idx) == 0) next
    if (length(idx) == 1) {
      out <- c(out, rownames(expr_scaled)[idx])
      next
    }
    sub_mat <- expr_scaled[idx, , drop = FALSE]
    ord_local <- tryCatch(hclust(dist(sub_mat))$order, error = function(e) seq_along(idx))
    out <- c(out, rownames(sub_mat)[ord_local])
  }
  out
}

# 绘制并保存热图
draw_heatmap <- function(expr_scaled, col_order, col_gaps, row_order,
                          row_anno = NULL, anno_colors = NULL,
                          col_anno = NULL,
                          row_gaps = NULL, out_pdf,
                          cluster_rows = FALSE, cluster_cols = FALSE,
                          show_rownames = TRUE,
                          dynamic_cell = FALSE,
                          fig_width = 10,
                          fig_height = 15) {
  mat_plot <- expr_scaled[row_order, col_order, drop = FALSE]

  cellheight <- 8
  cellwidth <- 12
  if (dynamic_cell) {
    n_gene <- nrow(mat_plot)
    n_sample <- ncol(mat_plot)
    # 预留边距/树状图空间后再计算格子大小，避免大矩阵被裁切
    usable_h <- max(fig_height * 72 - 140, 20)
    usable_w <- max(fig_width  * 72 - 120, 20)
    cellheight <- usable_h / max(n_gene, 1)
    cellwidth  <- usable_w / max(n_sample, 1)
    cellheight <- max(min(cellheight, 12), 0.1)
    cellwidth  <- max(min(cellwidth, 20), 0.5)
  }

  n_half      <- 50
  neg_cols    <- colorRampPalette(c("navy", "white"))(n_half)
  pos_cols    <- colorRampPalette(c("white", "#FFB347", "firebrick3"))(n_half)
  heat_colors <- c(neg_cols, "white", pos_cols)
  lim         <- max(abs(mat_plot), na.rm = TRUE)
  heat_breaks <- seq(-lim, lim, length.out = length(heat_colors) + 1)

  while (!is.null(dev.list())) dev.off()
  grDevices::cairo_pdf(out_pdf, width = fig_width, height = fig_height, bg = "white")

  pheatmap(
    mat_plot,
    annotation_row       = row_anno,
    annotation_names_row = !is.null(row_anno),
    annotation_colors    = anno_colors,
    annotation_col       = col_anno,
    fontsize             = 10,
    show_colnames        = FALSE,
    gaps_col             = col_gaps,
    gaps_row             = row_gaps,
    show_rownames        = show_rownames,
    fontsize_row         = 7,
    cellheight           = cellheight,
    cluster_rows         = cluster_rows,
    cluster_cols         = cluster_cols,
    annotation_legend    = TRUE,
    color                = heat_colors,
    breaks               = heat_breaks,
    cellwidth            = cellwidth,
    fontsize_col         = 11
  )

  dev.off()
  message("Saved: ", out_pdf)
}

# ===============================
# 4a. Mode 1: Top N by Variance
# ===============================
message("[4a] Mode 1: Top ", n_var, " genes by variance...")

gene_var      <- apply(fpkm_mat, 1, var, na.rm = TRUE)
n_use         <- min(n_var, length(gene_var))
top_genes_var <- names(sort(gene_var, decreasing = TRUE))[seq_len(n_use)]

expr_scaled_var <- scale_expr(fpkm_mat[top_genes_var, ])
row_order_var   <- rownames(expr_scaled_var)
col_order_var   <- colnames(expr_scaled_var)
col_anno_var    <- col_anno_from_cols(col_order_var)

draw_heatmap(
  expr_scaled = expr_scaled_var,
  col_order   = col_order_var,
  col_gaps    = NULL,
  row_order   = row_order_var,
  col_anno    = col_anno_var,
  anno_colors = list(Group = group_colors),
  out_pdf     = paste0(out_prefix, ".variance.pdf"),
  cluster_rows = TRUE,
  cluster_cols = TRUE,
  show_rownames = FALSE,
  dynamic_cell = TRUE,
  fig_width = 12,
  fig_height = 14
)

# ===============================
# 4b. Mode 2: Top N DEG (up + down)
# ===============================
if (!is.null(deg_up_fp) && !is.null(deg_down_fp)) {
  message("[4b] Mode 2: Top ", n_deg, " DEG up + down by |log2FC|...")

  if (!file.exists(deg_up_fp))   die("DEG up file not found: ", deg_up_fp)
  if (!file.exists(deg_down_fp)) die("DEG down file not found: ", deg_down_fp)

  deg_up   <- read.csv(deg_up_fp,   stringsAsFactors = FALSE)
  deg_down <- read.csv(deg_down_fp, stringsAsFactors = FALSE)

  if (!("gene_id" %in% colnames(deg_up)))   die("DEG up file missing required column: gene_id")
  if (!("gene_id" %in% colnames(deg_down))) die("DEG down file missing required column: gene_id")

  deg_up$gene_id   <- as.character(deg_up$gene_id)
  deg_down$gene_id <- as.character(deg_down$gene_id)

  # 各取 top N（按 |log2FC| 降序）
  top_up   <- deg_up   %>%
    arrange(desc(abs(log2FoldChange))) %>%
    slice_head(n = n_deg) %>%
    pull(gene_id)
  top_up <- unique(top_up)

  top_down <- deg_down %>%
    arrange(desc(abs(log2FoldChange))) %>%
    slice_head(n = n_deg) %>%
    pull(gene_id)
  top_down <- unique(top_down)

  # 合并（up 在前，down 中已出现在 up 的跳过）
  down_only <- top_down[!top_down %in% top_up]
  deg_genes <- unique(c(top_up, down_only))

  # 与 FPKM(gene_id) 矩阵取交集
  deg_genes_use <- intersect(deg_genes, rownames(fpkm_mat_id))
  if (length(deg_genes_use) == 0) die("No overlap between DEG genes and FPKM matrix")

  fpkm_mode2 <- fpkm_mat_id
  if (!is.null(deg_groups_str) && nzchar(deg_groups_str)) {
    deg_groups <- trimws(strsplit(deg_groups_str, ",")[[1]])
    deg_groups <- deg_groups[nzchar(deg_groups)]
    keep_idx <- which(as.character(metadata_ordered$Treat) %in% deg_groups)
    if (length(keep_idx) >= 2) {
      fpkm_mode2 <- fpkm_mat_id[, keep_idx, drop = FALSE]
    } else {
      warning("No sufficient samples matched --deg_groups=", deg_groups_str,
              "; using all samples in Mode 2.")
    }
  } else {
    message("[4b] --deg_groups not provided; using all samples in Mode 2.")
  }

  expr_scaled_deg <- scale_expr(fpkm_mode2[deg_genes_use, , drop = FALSE])
  row_order_deg   <- rownames(expr_scaled_deg)
  col_order_deg   <- colnames(expr_scaled_deg)
  col_anno_deg    <- col_anno_from_cols(col_order_deg)

  # Mode 2 画布高度与 Mode 1 对齐（更紧凑）
  fig_height_deg <- 14

  draw_heatmap(
    expr_scaled = expr_scaled_deg,
    col_order   = col_order_deg,
    col_gaps    = NULL,
    row_order   = row_order_deg,
    col_anno    = col_anno_deg,
    anno_colors = list(Group = group_colors),
    out_pdf     = paste0(out_prefix, ".DEG.pdf"),
    cluster_rows = TRUE,
    cluster_cols = TRUE,
    show_rownames = FALSE,
    dynamic_cell = TRUE,
    fig_width = 12,
    fig_height = fig_height_deg
  )
} else {
  message("[4b] Mode 2 skipped (--deg_up and --deg_down not both provided)")
}

# ===============================
# 4c. Mode 3: Module-based
# ===============================
if (!is.null(module_fp)) {
  message("[4c] Mode 3: Module-based heatmap...")

  if (!file.exists(module_fp)) die("Module file not found: ", module_fp)

  module <- read.csv(module_fp, stringsAsFactors = FALSE, check.names = FALSE)

  if (!all(c("DR_gene_symbol", "Type") %in% colnames(module))) {
    die("Module file missing required columns: DR_gene_symbol, Type")
  }

  # 清理空白，避免模块名/基因名因前后空格导致匹配异常
  module$DR_gene_symbol <- trimws(as.character(module$DR_gene_symbol))
  module$Type <- trimws(as.character(module$Type))

  # 模块内顺序
  module$order_in_module <- ave(
    seq_len(nrow(module)),
    module$Type,
    FUN = seq_along
  )

  genes_use <- intersect(rownames(fpkm_mat), module$DR_gene_symbol)
  if (length(genes_use) == 0) die("No overlapping genes between FPKM and module file")

  expr_scaled_mod <- scale_expr(fpkm_mat[genes_use, ])

  # 行注释
  row_module_chr <- module$Type[match(genes_use, module$DR_gene_symbol)]
  if (any(is.na(row_module_chr))) {
    bad_n <- sum(is.na(row_module_chr))
    die("Mode 3 module mapping failed: ", bad_n,
        " genes have no matched module Type after matching DR_gene_symbol")
  }

  row_anno <- data.frame(
    Module = row_module_chr,
    row.names = genes_use,
    check.names = FALSE
  )

  if (!is.null(module_order_str)){
    module_levels <- trimws(strsplit(module_order_str, ",")[[1]])
    module_levels <- module_levels[nzchar(module_levels)]
    unknown_modules <- setdiff(unique(row_anno$Module), module_levels)
    if (length(unknown_modules) > 0) {
      warning("Modules not found in --module_order and appended at end: ",
              paste(unknown_modules, collapse = ", "))
      module_levels <- c(module_levels, unknown_modules)
    }
    row_anno$Module <- factor(row_anno$Module, levels = unique(module_levels))
  }

  # 行顺序：按模块分块，模块内自动聚类
  if (is.factor(row_anno$Module)) {
    module_fac <- row_anno$Module
  } else {
    module_fac <- factor(row_anno$Module, levels = unique(as.character(row_anno$Module)))
  }
  row_order_mod <- order_rows_within_module(expr_scaled_mod, module_fac)

  # 行 gap（模块边界）
  module_labels <- row_anno[row_order_mod, "Module"]
  module_counts <- table(factor(module_labels, levels = levels(module_fac)))
  module_counts <- module_counts[module_counts > 0]
  row_gaps_mod  <- cumsum(module_counts)[-length(module_counts)]

  # 自动为每个模块分配颜色
  module_names    <- unique(as.character(row_anno$Module))
  default_palette <- c("#E74C3C", "#3498DB", "#9B59B6", "#2ECC71",
                        "#F39C12", "#1ABC9C", "#E67E22", "#95A5A6")
  auto_colors     <- setNames(default_palette[seq_along(module_names)], module_names)
  anno_colors_mod <- list(Module = auto_colors, Group = group_colors)
  col_order_mod <- order_cols_within_group(expr_scaled_mod, colnames(expr_scaled_mod), group_labels)
  col_anno_mod <- col_anno_from_cols(col_order_mod)

  draw_heatmap(
    expr_scaled = expr_scaled_mod,
    col_order   = col_order_mod,
    col_gaps    = col_gaps,
    row_order   = row_order_mod,
    row_anno    = row_anno,
    col_anno    = col_anno_mod,
    anno_colors = anno_colors_mod,
    row_gaps    = row_gaps_mod,
    out_pdf     = paste0(out_prefix, ".module.pdf"),
    cluster_rows = FALSE,
    cluster_cols = FALSE
  )
} else {
  message("[4c] Mode 3 skipped (--module not provided)")
}

message("All done.")
