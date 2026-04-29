# 屏蔽 package attach 时的“startup message”
suppressPackageStartupMessages({
  library(DESeq2)
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

counts_fp  <- get_arg("counts")
meta_fp    <- get_arg("meta")
filter_exp <- get_arg("filter", NULL)
design_var <- get_arg("design")
treat      <- get_arg("treat")
control    <- get_arg("control")
outdir     <- get_arg("outdir", "DEG_out")
prefix     <- get_arg("prefix", "DEG")
lfc_cutoff <- as.numeric(get_arg("lfc", 1.5))
p_cutoff   <- as.numeric(get_arg("p", 0.05))
p_col      <- get_arg("p_col", "padj")

# 必要参数检查
if (is.null(counts_fp) || is.null(meta_fp) || is.null(design_var) ||
    is.null(treat) || is.null(control)) {
  die("Required: --counts --meta --design --treat --control [--filter] [--outdir] [--prefix] [--lfc] [--p] [--p_col]")
}

if (!file.exists(counts_fp)) die("Counts file not found: ", counts_fp)
if (!file.exists(meta_fp))   die("Metadata file not found: ", meta_fp)

dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
# ===============================
# 1. 读取原始数据
# ===============================
message("[1/5] Read input ...")
count_mat <- read.csv(counts_fp, row.names = 1, check.names = FALSE)
metadata  <- read.csv(meta_fp,   row.names = 1, check.names = FALSE)

# ===============================
# 2. 取比对的子集样本（可选）
# ===============================
if (!is.null(filter_exp)) {
  message("[2/5] Filter metadata: ", filter_exp)
  keep <- with(metadata, eval(parse(text = filter_exp)))
  if (!is.logical(keep)) die("--filter must evaluate to a logical vector.")
  metadata <- metadata[keep, , drop = FALSE]
  if (nrow(metadata) < 2) die("Too few samples after filtering metadata.")
}
# ===============================
# 3. 对齐 counts 与 metadata
# ===============================
message("[3/5] Align samples ...")
common <- intersect(colnames(count_mat), rownames(metadata))
if (length(common) < 2) die("Too few common samples between counts and metadata.")

metadata  <- metadata[common, , drop = FALSE]
count_mat <- count_mat[, common, drop = FALSE]

# 严格保证顺序一致
metadata <- metadata[colnames(count_mat), , drop = FALSE]
stopifnot(all(colnames(count_mat) == rownames(metadata)))
# ===============================
# 4. 构建 DESeq2 对象并计算
# ===============================
message("[4/5] Run DESeq2 ...")

if (!design_var %in% colnames(metadata)) {
  die("Design variable not found in metadata: ", design_var)
}

metadata[[design_var]] <- factor(metadata[[design_var]])

if (!control %in% levels(metadata[[design_var]])) die("Control level not found: ", control)
if (!treat   %in% levels(metadata[[design_var]])) die("Treat level not found: ", treat)

metadata[[design_var]] <- relevel(metadata[[design_var]], ref = control)

dds <- DESeqDataSetFromMatrix(
  countData = as.matrix(count_mat),
  colData   = metadata,
  design    = as.formula(paste0("~ ", design_var))
)

dds <- DESeq(dds)
res <- results(dds, contrast = c(design_var, treat, control))
res_df <- as.data.frame(res)
res_df$gene_id <- rownames(res_df)
# ===============================
# 5. 生成结果文件
# ===============================
message("[5/5] Write outputs ...")

res_fp <- file.path(outdir, paste0(prefix, ".deseq2_results.csv"))
write.csv(res_df, res_fp, row.names = FALSE)

# 可选：保存对象以便调试/复用
saveRDS(dds, file.path(outdir, paste0(prefix, ".dds.rds")))
saveRDS(res, file.path(outdir, paste0(prefix, ".res.rds")))

# ===============================
# 5. 筛选DEG
# ===============================
if (!p_col %in% colnames(res_df)) die("p_col not found in results: ", p_col)

deg_all <- res_df %>%
  filter(!is.na(.data[[p_col]])) %>%
  filter(abs(log2FoldChange) >= lfc_cutoff, .data[[p_col]] <= p_cutoff)

deg_up <- deg_all %>% filter(log2FoldChange >= lfc_cutoff)
deg_down <- deg_all %>% filter(log2FoldChange <= -lfc_cutoff)

write.csv(deg_all,  file.path(outdir, paste0(prefix, ".DEG_all.csv")),  row.names = FALSE)
write.csv(deg_up,   file.path(outdir, paste0(prefix, ".DEG_up.csv")),   row.names = FALSE)
write.csv(deg_down, file.path(outdir, paste0(prefix, ".DEG_down.csv")), row.names = FALSE)

message("DEG selected: all=", nrow(deg_all), " up=", nrow(deg_up), " down=", nrow(deg_down))
message("Done: ", res_fp)
