# 加载必要包
library(ggplot2)
library(dplyr)
library(readr)
library(tidytext)
library(ggnewscale)


# ------------------------------
# 1. 函数：读取DEG文件并提取gene symbol（gene_name），并可保存为文件
# ------------------------------
extract_symbol <- function(file, out_file = NULL){
  deg <- read.csv(file, stringsAsFactors = FALSE)
  
  # 生成 gene_name：取竖线后半段
  deg$gene_name <- sapply(deg$gene_id, function(x) {
    if (grepl("\\|", x)) {
      strsplit(x, "\\|")[[1]][2]
    } else {
      x
    }
  })
  
  # 去掉 NA / 空字符串 + 去重
  symbols <- unique(deg$gene_name[!is.na(deg$gene_name) & deg$gene_name != ""])
  
  # 保存文件（每行一个symbol）
  if (!is.null(out_file)) {
    write.table(symbols, file = out_file, quote = FALSE,
                row.names = FALSE, col.names = FALSE)
  }
  
  return(symbols)
}

# ------------------------------
# 2. 读取六个DEG文件（上调和下调）
# ------------------------------
deg_files_up <- c("DEG_3M_MU_vs_WT_up.csv",
                  "DEG_6M_MU_vs_WT_up.csv",
                  "DEG_6M_SMU_vs_WT_up.csv")
deg_files_down <- c("DEG_3M_MU_vs_WT_down.csv",
                    "DEG_6M_MU_vs_WT_down.csv",
                    "DEG_6M_SMU_vs_WT_down.csv")
group_names <- c("3M Mutant","6M Mutant","6M Sick Mutant")

# 输出文件名：在原csv同目录下，xxx_up_symbols.txt / xxx_down_symbols.txt
out_up   <- sub("\\.csv$", "_symbols.txt", deg_files_up)
out_down <- sub("\\.csv$", "_symbols.txt", deg_files_down)

list_up_symbols   <- mapply(extract_symbol, deg_files_up,   out_up,   SIMPLIFY = FALSE)
list_down_symbols <- mapply(extract_symbol, deg_files_down, out_down, SIMPLIFY = FALSE)
# 合并 3 个上调 gene symbol 列表
# 给列表命名（每一列在 Metascape 中对应一个 gene list）
names(list_up_symbols) <- c("UP_3M", "UP_6M", "UP_6SM")

# 计算最大长度
max_len_up <- max(sapply(list_up_symbols, length))

# 补齐长度并转成 data.frame
metascape_up_df <- as.data.frame(
  lapply(list_up_symbols, function(x){
    length(x) <- max_len_up
    return(x)
  }),
  stringsAsFactors = FALSE
)

# 写出 CSV（供 Metascape 多列表上传）
write.csv(
  metascape_up_df,
  file = "Metascape_UP_multiple_SYMBOL.csv",
  row.names = FALSE,
  quote = FALSE
)

# 合并 3 个下调 gene symbol 列表
names(list_down_symbols) <- c("DOWN_3M", "DOWN_6M", "DOWN_6SM")

max_len_down <- max(sapply(list_down_symbols, length))

metascape_down_df <- as.data.frame(
  lapply(list_down_symbols, function(x){
    length(x) <- max_len_down
    return(x)
  }),
  stringsAsFactors = FALSE
)

write.csv(
  metascape_down_df,
  file = "Metascape_DOWN_multiple_SYMBOL.csv",
  row.names = FALSE,
  quote = FALSE
)
# ------------------------------------------------
# 在metascape网站上进行GO和KEGG富集分析
# ------------------------------------------------
# 对网站生成的结果进行数据处理，导入处理后的结果表
up_go <- read_csv("up_go.csv")
down_go <- read_csv("down_go.csv")
up_kegg <- read_csv("up_kegg.csv")
down_kegg <- read_csv("down_kegg.csv")

up_go <- up_go %>%
  rename(Count = `#GeneInGOAndHitList`)
down_go <- down_go %>%
  rename(Count = `#GeneInGOAndHitList`)
# ------------------------------
# 定义模块和对应 GO term
# ------------------------------
go_modules <- list(
  "Digestion"   = c("steroid metabolic process",
                    "lipid transport",
                    "lipid digestion",
                    "intestinal absorption",
                    "drug metabolic process",
                    "digestion"),
  
  "Cell Cycle"  = c("stem cell differentiation",
                    "DNA replication",
                    "DNA repair",
                    "cell migration",
                    "cell division",
                    "cell cycle process"),
  
  "Immunity"    = c("response to virus",
                    "response to hormone",
                    "response to bacterium",
                    "inflammatory response",
                    "immune response",
                    "defense response")
)

# ------------------------------
# 生成 go_module_mapping
# ------------------------------
go_module_mapping <- data.frame(
  Description = unlist(go_modules),
  Module = rep(names(go_modules), times = sapply(go_modules, length)),
  stringsAsFactors = FALSE
)

# ------------------------------
# 添加 Direction 和 logP 列
# ------------------------------
up_go <- up_go %>%
  mutate(Direction = "Up",
         logP = minus_logq,  # 根据你表格实际列名修改
         Module = go_module_mapping$Module[match(Description, go_module_mapping$Description)])

down_go <- down_go %>%
  mutate(Direction = "Down",
         logP = `Log(q-value)`,  # 下调取负值
         Module = go_module_mapping$Module[match(Description, go_module_mapping$Description)])

# ------------------------------
# 合并上调/下调
# ------------------------------
go_df <- bind_rows(up_go, down_go)

# 可选择只保留有对应 Module 的 GO term
go_df <- go_df %>% filter(!is.na(Module))
go_df <- bind_rows(up_go, down_go) %>%
  filter(!is.na(Module)) %>%
  filter(grepl("3M|6M|6SM", GeneList)) %>%   # <- 去掉末尾 |
  mutate(
    Group = case_when(
      grepl("3M", GeneList, ignore.case = TRUE) ~ "3 Months Mutant",
      grepl("6SM", GeneList, ignore.case = TRUE) ~ "6 Months Sick Mutant",
      grepl("6M", GeneList, ignore.case = TRUE) ~ "6 Months Mutant",
      TRUE ~ NA_character_
    ),
    GroupDir = interaction(Group, Direction, lex.order = TRUE),
    # 锁定顺序：每组左Up右Down
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
    # 给每个组一个基准位置：1 / 4 / 7（组间距离大）
    group_base = case_when(
      Group == "3 Months Mutant" ~ 1,
      Group == "6 Months Mutant" ~ 4,
      Group == "6 Months Sick Mutant" ~ 7,
      TRUE ~ NA_real_
    ),
    # 同组两列靠近：Up 在左（-0.25），Down 在右（+0.25）
    x_pos = group_base + ifelse(Direction == "Up", -0.5, 0.5)
  )


# ------------------------------
# 绘制GO气泡图
# ------------------------------

qs <- quantile(go_df$logP, probs = c(0, 0.2, 0.35, 0.5, 0.65, 0.8, 1), na.rm = TRUE)


# 建议：Down 用正值表示“下调强度”，更接近论文的 DOWN logP
go_up   <- go_df %>% dplyr::filter(Direction == "Up")
go_down <- go_df %>% dplyr::filter(Direction == "Down") %>%
  dplyr::mutate(logP_down = abs(logP))   # 下调取绝对值作为强度

ggplot() +
  # --- Up layer ---
  geom_point(data = go_up,
             aes(x = x_pos, y = Description_f, size = Count, color = logP),
             alpha = 0.9) +
  scale_color_gradient(
    low  = "orange",
    high = "red",
    name = "UP logP"
  ) +
  ggnewscale::new_scale_color() +
  
  # --- Down layer ---
  geom_point(data = go_down,
             aes(x = x_pos, y = Description_f, size = Count, color = logP_down),
             alpha = 0.9) +
  scale_color_gradient(
    low  = "#33CCFF",
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
  theme(strip.background = element_rect(fill = "#F4B6C2"),
        axis.title.x = element_blank(),
        plot.margin = margin(t = 70, r = 40, b = 5, l = 40) )
# -------------------------------------
# KEGG
# -------------------------------------

# 论文里选的通路列表
selected_pathways <- c(
  "Vitamin digestion and absorption",
  "Protein digestion and absorption",
  "PPAR signaling pathway",
  "Fatty acid degradation",
  "Fat digestion and absorption",
  "p53 signaling pathway",
  "Homologous recombination",
  "Cytokine-cytokine receptor interaction",
  "Cell cycle",
  "Cell adhesion molecules"
)

# 合并 UP/DOWN
kegg_df <- bind_rows(up_kegg, down_kegg)

# 创建统一的 Group_simple
kegg_df <- kegg_df %>%
  mutate(Group = case_when(
    grepl("3M", GeneList) ~ "3 Months Mutant",
    grepl("6M$", GeneList) ~ "6 Months Mutant",
    grepl("6SM", GeneList) ~ "6 Months Sick Mutant",
    TRUE ~ NA_character_
  )) %>%
  filter(!is.na(Group)) %>%
  mutate(logP = minus_logq)  # 或 -log10(q_value)

#  每个通路 × 组取 logP 最大值
kegg_df <- kegg_df %>%
  group_by(Group, Description) %>%
  summarise(logP = max(logP, na.rm = TRUE), .groups = "drop")

#  补全指定通路（保证每个组都有 selected_pathways）
kegg_plot_df <- expand.grid(
  Group = unique(kegg_df$Group),
  Description = selected_pathways,
  stringsAsFactors = FALSE
) %>%
  left_join(kegg_df, by = c("Group", "Description")) %>%
  mutate(logP = ifelse(is.na(logP), 0, logP))



# 4. 设置纵轴顺序（固定顺序）
kegg_plot_df$Description <- factor(kegg_plot_df$Description, levels = rev(selected_pathways))

# 绘制KEGG柱状图
# 计算最大值

ggplot(kegg_plot_df, aes(x = logP, y = Description, fill = Group)) +
  geom_col(color = "black", width = 0.7) +
  facet_wrap(~ Group, ncol = 3, scales = "fixed") +
  scale_fill_manual(
    values = c(
      "3 Months Mutant" = "lightblue",
      "6 Months Mutant" = "lightyellow",
      "6 Months Sick Mutant" = "lightpink"
    )
  ) +
  scale_x_continuous(
    limits = c(0, 20),                 # 最大值手动设置为20
    breaks = seq(0, 20, by = 4),       # 刻度间隔自定义
    expand = c(0, 0)
  ) +
  labs(
    x = "-logP",
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
    legend.position = "none",  # 如果不需要图例，可以加上
    panel.spacing = unit(0.5, "cm")  # ← 调整小图之间距离
  )

