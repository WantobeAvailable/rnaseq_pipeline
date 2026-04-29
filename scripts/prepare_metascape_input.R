suppressPackageStartupMessages({
  library(dplyr)
})

die <- function(...) stop(paste0(...), call. = FALSE)

# ===============================
# 0. 参数
# ===============================
args <- commandArgs(trailingOnly = TRUE)

get_arg <- function(flag, default = NULL){
  i <- match(paste0("--", flag), args)
  if (is.na(i)) return(default)
  if (i == length(args)) die("Missing value for --", flag)
  args[i + 1]
}

counts_dir <- get_arg("counts_dir", NULL)

if (is.null(counts_dir)) die("Required: --counts_dir")
if (!dir.exists(counts_dir)) die("Counts dir not found: ", counts_dir)

# ===============================
# 1. gene symbol 提取函数
# ===============================
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

# ===============================
# 2. 自动收集 up/down 文件
# ===============================
message("[1/3] Scanning DEG files in: ", counts_dir)

deg_up_files <- list.files(counts_dir, pattern = "\\.DEG_up\\.csv$", full.names = TRUE)
deg_down_files <- list.files(counts_dir, pattern = "\\.DEG_down\\.csv$", full.names = TRUE)

if (length(deg_up_files) == 0) die("No DEG_up files found in ", counts_dir)
if (length(deg_down_files) == 0) die("No DEG_down files found in ", counts_dir)

# 对比名提取：prefix = 去掉 .DEG_up.csv
prefix_up <- sub("\\.DEG_up\\.csv$", "", basename(deg_up_files))
prefix_down <- sub("\\.DEG_down\\.csv$", "", basename(deg_down_files))

# ===============================
# 3. 提取 symbol + 输出 txt
# ===============================
message("[2/3] Extracting symbols...")

list_up_symbols <- list()
list_down_symbols <- list()

# UP
for(i in seq_along(deg_up_files)){
  p <- prefix_up[i]
  out_txt <- file.path(counts_dir, paste0(p, "_UP_symbols.txt"))
  list_up_symbols[[p]] <- extract_symbol(deg_up_files[i], out_txt)
}

# DOWN
for(i in seq_along(deg_down_files)){
  p <- prefix_down[i]
  out_txt <- file.path(counts_dir, paste0(p, "_DOWN_symbols.txt"))
  list_down_symbols[[p]] <- extract_symbol(deg_down_files[i], out_txt)
}

# ===============================
# 4. 输出 Metascape 多列表 CSV
# ===============================
message("[3/3] Writing Metascape multiple-list CSV...")

make_metascape_df <- function(symbol_list){
  max_len <- max(sapply(symbol_list, length))
  as.data.frame(
    lapply(symbol_list, function(x){
      length(x) <- max_len
      return(x)
    }),
    stringsAsFactors = FALSE
  )
}

metascape_up_df <- make_metascape_df(list_up_symbols)
write.csv(metascape_up_df,
          file = file.path(counts_dir, "Metascape_UP_multiple_SYMBOL.csv"),
          row.names = FALSE,
          quote = FALSE)

metascape_down_df <- make_metascape_df(list_down_symbols)
write.csv(metascape_down_df,
          file = file.path(counts_dir, "Metascape_DOWN_multiple_SYMBOL.csv"),
          row.names = FALSE,
          quote = FALSE)

message("Metascape input files written to: ", counts_dir)