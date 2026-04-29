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

meta_fp  <- get_arg("meta")               # 样本信息文件

if (!file.exists(meta_fp)) die("Metadata file not found: ", meta_fp)
# 把 13 个样本的 geneBodyCoverage 曲线画到一张图

r_files <- list.files(pattern = "_geneBody\\.geneBodyCoverage\\.r$")
stopifnot(length(r_files) > 0)

# 读入每个 r 文件，提取 SRRxxx.sorted 变量
curve_list <- list()

# 临时屏蔽 pdf() 和 dev.off()
pdf_backup <- pdf
devoff_backup <- dev.off

pdf <- function(...) invisible(NULL)
dev.off <- function(...) invisible(NULL)

for (f in r_files) {
  env <- new.env()
  source(f, local = env)
  
  objname <- ls(env)[grepl("\\.sorted$", ls(env))]
  if (length(objname) != 1) {
    stop(paste("文件中找不到唯一的 *.sorted 向量：", f))
  }
  
  sample_id <- sub("\\.sorted$", "", objname)
  curve_list[[sample_id]] <- get(objname, envir = env)
}

# 恢复函数
pdf <- pdf_backup
dev.off <- devoff_backup

# 按 SRR 编号排序（可选）
curve_list <- curve_list[sort(names(curve_list))]

# 读入 metadata（包含 run_id 和 SampleID）
meta <- read.csv(meta_fp, stringsAsFactors = FALSE)

# 读入曲线（你的 curve_list 已经做好了就不用再跑一遍）
# curve_list 的名字应为 SRR16972425 这种

# 按 curve_list 的顺序生成 legend 标签
legend_labels <- meta$sample_id[match(names(curve_list), meta$run_id)]

# 防止匹配失败（NA）
if (any(is.na(legend_labels))) {
  stop("metadata.csv 里有 run_id 没匹配上 curve_list 的样本名，请检查 run_id 是否一致")
}

# ========== 开始画图 ==========
pdf("geneBodyCoverage.pdf", width=8.5, height=5, useDingbats=FALSE)

x <- 1:100
# cols <- hcl.colors(length(curve_list), palette = "Dark 3")
cols <- rainbow(length(curve_list))

# 关键：加大右侧空白（mar 的第4个值是右边距）
par(mar=c(5,5,4,10), xpd=TRUE)

plot(x, curve_list[[1]], type="l", lwd=0.3, col=cols[1],
     xlab="Gene body percentile (5'->3')",
     ylab="Coverage",
     main="GeneBody coverage (13 samples)",
     ylim=range(unlist(curve_list)))

i <- 1
for (nm in names(curve_list)) {
  lines(x, curve_list[[nm]], lwd=0.3, col=cols[i])
  i <- i + 1
}

# 图例放到图外（右侧）
par(fig=c(0.78, 0.98, 0.10, 0.90), new=TRUE, mar=c(0,0,0,0))
plot.new()
legend("center", legend=legend_labels, col=cols, lwd=0.3, cex=0.85, bty="n")

dev.off()
cat("Done: geneBodyCoverage.pdf\n")
while (dev.cur() > 1) dev.off()
