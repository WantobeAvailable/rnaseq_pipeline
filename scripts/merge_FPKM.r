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

# 输出
out <- get_arg("o", "merged_FPKM.csv")

# ===============================
# 1. 合并FPKM表
# ===============================
files <- list.files(pattern = "*.gene_abund.txt", full.names = TRUE)
merged <- NULL

for(f in files){
  
  # 提取样本名，只保留文件名，不带路径
  sample_name <- basename(f)
  sample_name <- sub("\\.gene_abund.txt$", "", sample_name)
  
  # 读取文件
  df <- read.table(f, header=TRUE, sep="\t", stringsAsFactors=FALSE)
  
  # 保留注释列 + FPKM
  df <- df[, c("Gene.ID", "Gene.Name", "Reference", "Strand", "Start", "End", "FPKM")]
  
  # 重命名 FPKM 列为样本名
  colnames(df)[7] <- sample_name
  
  # 合并
  if(is.null(merged)){
    merged <- df
  } else {
    merged <- merge(merged, df, by=c("Gene.ID","Gene.Name","Reference","Strand","Start","End"), all=TRUE)
  }
}

write.csv(merged, out, row.names = FALSE)
message("合并完成，输出文件",out)
