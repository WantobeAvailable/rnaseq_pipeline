
suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(readr)
  library(grid)
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

indir   <- get_arg("indir", NULL)                 # 结果文件所在目录（counts）
up_fp   <- get_arg("up_kegg", "up_kegg.csv")      # 可以只给文件名（在 indir 下）或给绝对路径
down_fp <- get_arg("down_kegg", "down_kegg.csv")
pathways_fp <- get_arg("pathways", "kegg_pathways.txt")
sig_metric <- get_arg("significance", "pvalue")

if (!(sig_metric %in% c("pvalue", "padjust", "qvalue"))) {
  die("Invalid --significance: ", sig_metric, ". Use one of: pvalue, padjust, qvalue")
}

if (is.null(indir)) die("Required: --indir (directory contains up_kegg.csv/down_kegg.csv)")
if (!dir.exists(indir)) die("indir not found: ", indir)

# 拼出真实路径（如果用户传的是相对名，就默认在 indir 下）
resolve_path <- function(p) {
  if (file.exists(p)) return(p)
  p2 <- file.path(indir, p)
  if (file.exists(p2)) return(p2)
  die("File not found: ", p, " (also tried: ", p2, ")")
}

up_fp_full   <- resolve_path(up_fp)
down_fp_full <- resolve_path(down_fp)

out_png_full <- file.path(indir, "KEGG_barplot.png")
out_pdf_full <- file.path(indir, "KEGG_barplot.pdf")

# ===============================
# 1. 读取 Metascape KEGG 结果
# ===============================
up_kegg   <- read_csv(up_fp_full, show_col_types = FALSE)
down_kegg <- read_csv(down_fp_full, show_col_types = FALSE)

neglog10_safe <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  -log10(pmax(x, .Machine$double.xmin))
}

# 兼容并补全当前输出字段：LogP / LogP_adjust / LogP_qvalue / Log(q-value) / minus_logq
up_kegg <- up_kegg %>%
  mutate(
    LogP = neglog10_safe(pvalue),
    LogP_adjust = neglog10_safe(p.adjust),
    LogP_qvalue = neglog10_safe(qvalue),
    `Log(q-value)` = LogP_qvalue,
    minus_logq = -LogP_qvalue
  )

down_kegg <- down_kegg %>%
  mutate(
    LogP = neglog10_safe(pvalue),
    LogP_adjust = neglog10_safe(p.adjust),
    LogP_qvalue = neglog10_safe(qvalue),
    `Log(q-value)` = LogP_qvalue,
    minus_logq = -LogP_qvalue
  )

pick_sig <- function(df) {
  if (sig_metric == "pvalue") return(df$LogP)
  if (sig_metric == "padjust") return(df$LogP_adjust)
  df$LogP_qvalue
}

pick_group_source <- function(df) {
  if ("group" %in% colnames(df)) return(df$group)
  if ("GeneList" %in% colnames(df)) return(df$GeneList)
  die("No group label column found. Expected 'group' or 'GeneList'.")
}

# ===============================
# 2. 读取/定义 selected_pathways（只参数化，不改后续绘图逻辑）
# ===============================

  pathways_fp <- resolve_path(pathways_fp)
  
  selected_pathways <- readLines(pathways_fp, warn = FALSE)
  selected_pathways <- selected_pathways[nzchar(selected_pathways)]
  
  if (length(selected_pathways) == 0) {
    die("KEGG pathway list file is empty: ", pathways_fp)
  }
  

# ===============================
# 3. KEGG（下面基本保持你的逻辑不动）
# ===============================

# 合并 UP/DOWN
kegg_df <- bind_rows(up_kegg, down_kegg)

# 创建统一的 Group_simple
  kegg_df <- kegg_df %>%
    mutate(
      Group = as.character(pick_group_source(.)),
      logP = pick_sig(.)
    ) %>%
    filter(!is.na(Group), Group != "")
  
# 每个通路 × 组取 logP 最大值
kegg_df <- kegg_df %>%
  group_by(Group, Description) %>%
  summarise(logP = max(logP, na.rm = TRUE), .groups = "drop")

# 补全指定通路（保证每个组都有 selected_pathways）
kegg_plot_df <- expand.grid(
  Group = unique(kegg_df$Group),
  Description = selected_pathways,
  stringsAsFactors = FALSE
) %>%
  left_join(kegg_df, by = c("Group", "Description")) %>%
  mutate(logP = ifelse(is.na(logP), 0, logP))

# 设置纵轴顺序（固定顺序）
kegg_plot_df$Description <- factor(kegg_plot_df$Description, levels = rev(selected_pathways))

# ===============================
# 4. 绘图
# ===============================
p <- ggplot(kegg_plot_df, aes(x = logP, y = Description, fill = Group)) +
  geom_col(color = "black", width = 0.7) +
  facet_wrap(~ Group, ncol = 3, scales = "fixed") +
  scale_x_continuous(
    limits = c(0, 20),
    breaks = seq(0, 20, by = 4),
    expand = c(0, 0)
  ) +
  labs(
    x = if (sig_metric == "pvalue") "LogP" else "-logFDR",
    y = "Selected KEGG pathway",
    title = "KEGG Pathway Enrichment Across Groups"
  ) +
  theme_bw() +
  theme(
    strip.background = element_rect(fill = "white"),
    strip.text = element_text(size = 10, face = "bold"),
    axis.text.y = element_text(size = 9),
    axis.title = element_text(size = 11, face = "bold"),
    plot.title = element_text(hjust = 0.5, size = 12, face = "bold"),
    legend.position = "none",
    panel.spacing = unit(0.5, "cm")
  )

# ===============================
# 5. 保存输出
# ===============================
ggsave(out_png_full, plot = p, width = 9, height = 5, dpi = 300)
ggsave(out_pdf_full, plot = p, width = 9, height = 5)

message("KEGG plot written to: ", out_png_full, " and ", out_pdf_full)
