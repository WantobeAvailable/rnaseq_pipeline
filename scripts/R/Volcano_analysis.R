suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(dplyr)
  library(ggrepel)
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

in_fp   <- get_arg("deg")              # 单对比 DEG 结果文件
out_pre <- get_arg("prefix", "Volcano")
lfc_cut <- as.numeric(get_arg("lfc", 1.5))
p_cut   <- as.numeric(get_arg("p", 0.05))
p_col   <- get_arg("p_col", "pvalue") # "pvalue" 或 "padj"
title   <- get_arg("title", out_pre)

if (is.null(in_fp)) die("Required: --in")
if (!file.exists(in_fp)) die("Input DEG file not found: ", in_fp)

# ==========================
# 1. 读取单对比 DEG 表
# ==========================
deg <- fread(in_fp, check.names = FALSE)

# 兼容你以前的 gene_id 格式（gene_id 里带 |）
if ("gene_id" %in% colnames(deg)) {
  deg$gene_id_st <- sub("\\|.*$", "", deg$gene_id)
  deg$gene_name  <- sub("^.*\\|", "", deg$gene_id)
} else if ("gene" %in% colnames(deg)) {
  deg$gene_id_st <- deg$gene
  deg$gene_name  <- deg$gene
} else {
  # 没有 gene 信息也能画，只是标注会用行名/NA
  deg$gene_name <- rownames(as.data.frame(deg))
}

# 如果你的表里 pvalue 列名不是 pvalue/padj，就用 --p_col 指定
if (!("log2FoldChange" %in% colnames(deg))) die("Missing column: log2FoldChange")
if (!(p_col %in% colnames(deg))) die("Missing p column: ", p_col)

# 统一列名，减少对 plot_volcano 的改动
deg$pvalue <- deg[[p_col]]
deg$contrast <- title
# ==========================
# 4. 定义火山图绘制函数
# ==========================
plot_volcano <- function(df, lfc, p){
  df <- df[!is.na(df$log2FoldChange) & !is.na(df$pvalue), ]
  df$change <- "Not significant"
  df[df$pvalue < p & df$log2FoldChange > lfc, "change"] <- "Up"
  df[df$pvalue < p & df$log2FoldChange < -lfc, "change"] <- "Down"  
  # 计算综合指标
  df$score <- -log10(df$pvalue) * abs(df$log2FoldChange)  
  # 在 Up / Down 中分别排序;再限制 log2FC 不能太接近
  top_genes <- df %>%
    filter(change %in% c("Up", "Down")) %>%
    group_by(change) %>%
    arrange(desc(score)) %>%       # score = |log2FC| * -log10(pvalue)
    slice_head(n = 5) %>%         # 每侧 Top 5
    ungroup()  
  p <- ggplot(df, aes(x = log2FoldChange,
                      y = -log10(pvalue),
                      color = change)) +
    geom_point(
      aes(fill = change, color = change),
      shape = 21,          # ★ 空心圆
      size = 2.2,
      alpha = 0.6,         # ★ 内部填充变淡
      stroke = 0.4         # ★ 边框线宽
    ) +
    scale_fill_manual(
      values = c(
        "Up" = "red",
        "Down" = "blue",
        "Not significant" = "grey80"
      )
    ) +
    scale_color_manual(
      values = c(
        "Up" = "red",
        "Down" = "blue",
        "Not significant" = "grey50"
      )
    ) +
    # 阈值线
    geom_vline(xintercept = c(-lfc, lfc),
               linetype = "dashed", linewidth = 0.4) +
    geom_hline(yintercept = -log10(p),
               linetype = "dashed", linewidth = 0.4) +
    # ★ 文字标注（重点）
    geom_text_repel(
      data = top_genes,
      aes(x = log2FoldChange, y = -log10(pvalue), label = gene_name),
      segment.color = NA,      # 不画连线
      color = "black",
      size = 3,
      max.overlaps = Inf
    ) +
    labs(
      title = unique(df$contrast),
      x = "log2(Fold Change)",
      y = "-log10(p-value)"
    ) +
    theme_bw() +
    theme(
      legend.title = element_blank()
    )
  return(p)
}

# ==========================
# 4. 画 + 保存(png+pdf) 火山图
# ==========================
p <- plot_volcano(deg, lfc = lfc_cut, p = p_cut)

ggsave(paste0(out_pre, ".png"), plot = p, width = 6, height = 5, dpi = 300)
pdf(paste0(out_pre, ".pdf"), width = 6, height = 5)
print(p)
dev.off()