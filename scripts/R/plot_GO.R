suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(readr)
  library(tidytext)
  library(ggnewscale)
})

die <- function(...) stop(paste0(...), call. = FALSE)

# ===============================
# 提取参数
# ===============================
args <- commandArgs(trailingOnly = TRUE)

get_arg <- function(flag, default=NULL){
  i <- match(paste0("--", flag), args)
  if (is.na(i)) return(default)
  if (i == length(args)) die("Missing value for --", flag)
  args[i + 1]
}

indir  <- get_arg("indir", "counts")
up_fp   <- get_arg("up_go", "up_go.csv")      # 可以只给文件名（在 indir 下）或给绝对路径
down_fp <- get_arg("down_go", "down_go.csv")
go_map_fp <- get_arg("go_map", "go_modules.tsv")
sig_metric <- get_arg("significance", "pvalue")

if (!(sig_metric %in% c("pvalue", "padjust", "qvalue"))) {
  die("Invalid --significance: ", sig_metric, ". Use one of: pvalue, padjust, qvalue")
}

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
go_map_full  <- resolve_path(go_map_fp)


# ===============================
# 读取 Metascape 输出结果
# ===============================
up_go    <- read_csv(up_fp_full, show_col_types = FALSE)
down_go  <- read_csv(down_fp_full, show_col_types = FALSE)

normalize_count_col <- function(df) {
  if ("Count" %in% colnames(df)) return(df)
  if ("Counts" %in% colnames(df)) return(df %>% rename(Count = Counts))
  if ("#GeneInGOAndHitList" %in% colnames(df)) return(df %>% rename(Count = `#GeneInGOAndHitList`))
  die("No count column found. Expected one of: Count, Counts, #GeneInGOAndHitList")
}

normalize_genelist_col <- function(df) {
  if ("GeneList" %in% colnames(df)) return(df)
  if ("group" %in% colnames(df)) return(df %>% mutate(GeneList = group))
  if ("geneID" %in% colnames(df)) return(df %>% mutate(GeneList = geneID))
  die("No GeneList column found. Expected one of: GeneList, group, geneID")
}

up_go <- normalize_count_col(up_go)
down_go <- normalize_count_col(down_go)
up_go <- normalize_genelist_col(up_go)
down_go <- normalize_genelist_col(down_go)

neglog10_safe <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  -log10(pmax(x, .Machine$double.xmin))
}

# 兼容并补全当前输出字段：LogP / LogP_adjust / LogP_qvalue / Log(q-value) / minus_logq
up_go <- up_go %>%
  mutate(
    LogP = neglog10_safe(pvalue),
    LogP_adjust = neglog10_safe(p.adjust),
    LogP_qvalue = neglog10_safe(qvalue),
    `Log(q-value)` = LogP_qvalue,
    minus_logq = -LogP_qvalue
  )

down_go <- down_go %>%
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


go_module_mapping <- read.delim(go_map_full, sep = "\t", stringsAsFactors = FALSE, check.names = FALSE)

# ------------------------------
# 添加 Direction 和 logP 列
# ------------------------------
up_go <- up_go %>%
  mutate(Direction = "Up",
         logP = pick_sig(up_go),
         Module = go_module_mapping$Module[match(Description, go_module_mapping$Description)])

down_go <- down_go %>%
  mutate(Direction = "Down",
         logP = -pick_sig(down_go),
         Module = go_module_mapping$Module[match(Description, go_module_mapping$Description)])

# ------------------------------
# 合并上调/下调
# ------------------------------
go_df <- bind_rows(up_go, down_go)


# 可选择只保留有对应 Module 的 GO term
go_df <- go_df %>%
  filter(!is.na(Module)) %>%
  filter(grepl("3M|6M|6SM|SMU", GeneList, ignore.case = TRUE)) %>%
  mutate(
    Group = case_when(
      grepl("6SM|SMU|sick", GeneList, ignore.case = TRUE) ~ "6 Months Sick Mutant",
      grepl("6M", GeneList, ignore.case = TRUE) ~ "6 Months Mutant",
      grepl("3M", GeneList, ignore.case = TRUE) ~ "3 Months Mutant",
      TRUE ~ NA_character_
    ),
    GroupDir = interaction(Group, Direction, lex.order = TRUE),
    GroupDir = factor(
      GroupDir,
      levels = c("3 Months Mutant.Up", "3 Months Mutant.Down",
                 "6 Months Mutant.Up", "6 Months Mutant.Down",
                 "6 Months Sick Mutant.Up", "6 Months Sick Mutant.Down")
    )
  ) %>%
  filter(!is.na(Group))

# ------------------------------
# 生成绘图用的强制顺序
# ------------------------------

go_df$Module <- factor(
  go_df$Module,
  levels = c("Digestion", "Cell Cycle", "Immunity")
)

go_df <- go_df %>%
  group_by(Module) %>%
  mutate(
    y_pos = row_number() * 1.5,
    Description_f = reorder_within(Description, y_pos, Module)
  ) %>%
  ungroup()

go_df <- go_df %>%
  mutate(
    group_base = case_when(
      Group == "3 Months Mutant" ~ 1,
      Group == "6 Months Mutant" ~ 4,
      Group == "6 Months Sick Mutant" ~ 7,
      TRUE ~ NA_real_
    ),
    x_pos = group_base + ifelse(Direction == "Up", -0.5, 0.5)
  )

# ------------------------------
# 绘制GO气泡图
# ------------------------------

go_up <- go_df %>% filter(Direction == "Up")
go_down <- go_df %>%
  filter(Direction == "Down") %>%
  mutate(logP_down = abs(logP))

p_go <- ggplot() +
  geom_point(
    data = go_up,
    aes(x = x_pos, y = Description_f, size = Count, color = logP),
    alpha = 0.9
  ) +
  scale_color_gradient(
    low = "orange",
    high = "red",
    name = "UP logP"
  ) +
  ggnewscale::new_scale_color() +
  geom_point(
    data = go_down,
    aes(x = x_pos, y = Description_f, size = Count, color = logP_down),
    alpha = 0.9
  ) +
  scale_color_gradient(
    low = "#33CCFF",
    high = "purple",
    name = "DOWN logP"
  ) +
  facet_grid(Module ~ ., scales = "free_y", space = "free_y") +
  scale_y_reordered() +
  scale_x_continuous(
    breaks = c(1, 4, 7),
    labels = c("3 Months\nMutant", "6 Months\nMutant", "6 Months\nSick Mutant")
  ) +
  theme_bw() +
  theme(
    strip.background = element_rect(fill = "#F4B6C2"),
    axis.title.x = element_blank(),
    plot.margin = margin(t = 70, r = 40, b = 5, l = 40)
  )

ggsave(file.path(indir, "GO_bubbleplot.png"),
       plot = p_go, width = 7, height = 6, dpi = 300)

ggsave(file.path(indir, "GO_bubbleplot.pdf"),
       plot = p_go, width = 7, height = 6)


message("GO plotting finished.")
