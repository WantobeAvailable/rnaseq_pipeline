# 屏蔽 package attach 时的“startup message”
suppressPackageStartupMessages({
  library(clusterProfiler)
  library(org.Dr.eg.db)
  library(org.Hs.eg.db)
  library(readxl)
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

deg_dir  <- get_arg("deg_dir")
species <- tolower(get_arg("species", get_arg("analysis_species", "zebrafish")))
species <- ifelse(species == "zeberfish", "zebrafish", species)
pattern_up  <- get_arg("pattern_up","DEG_up.csv")
pattern_down  <- get_arg("pattern_down","DEG_down.csv")
annotation_db <- get_arg("annotation_db", "rawdata/DR_HS_Gene_Annotation_zh3.xlsx")
dr_symbol_col_arg <- get_arg("dr_symbol_col", NULL)
hs_entrez_col_arg <- get_arg("hs_entrez_col", NULL)
outdir <- get_arg("outdir", deg_dir)


# 必要参数检查
if (is.null(deg_dir)) {
  die("Required: --deg_dir [--species human|zebrafish] [--pattern_up] [--pattern_down] [--annotation_db] [--outdir]")
}

if (!dir.exists(deg_dir)) die("DEG directory not found: ", deg_dir)
if (species == "human" && !file.exists(annotation_db)) {
  die("Annotation database not found: ", annotation_db)
}

dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

# ==========================================
# 1.函数
# ===========================================

# 1. 提取gene symbol（gene_name）
extract_symbol <- function(deg, out_file = NULL){

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

# 2.直接转换为Entrez ID
convert_to_entrez <- function(symbols, OrgDb){ 
  df <- bitr( 
    symbols,
    fromType = "SYMBOL",
    toType = "ENTREZID",
    OrgDb = OrgDb ) 
  
  unique(df$ENTREZID) 
}
# 3. 使用实验室注释表进行斑马鱼 SYMBOL -> 人类 ENTREZID 映射
normalize_colname <- function(x) {
  tolower(gsub("[^a-z0-9]+", "", trimws(as.character(x))))
}

find_column <- function(df, candidates, required = TRUE, label = "column") {
  nms <- colnames(df)
  nms_norm <- normalize_colname(nms)
  cand_norm <- unique(normalize_colname(candidates))
  hit <- which(nms_norm %in% cand_norm)

  if (length(hit) == 0 && required) {
    die("Cannot find ", label, " in annotation DB. Existing columns: ",
        paste(nms, collapse = ", "))
  }
  if (length(hit) == 0) return(NULL)
  nms[hit[1]]
}

read_lab_annotation_db <- function(annotation_fp, dr_symbol_col_arg = NULL, hs_entrez_col_arg = NULL) {
  anno <- as.data.frame(readxl::read_excel(annotation_fp), stringsAsFactors = FALSE)
  if (nrow(anno) == 0) die("Annotation DB is empty: ", annotation_fp)

  # 调试信息：Linux 服务器可通过日志直接查看列名与规范化结果
  message("Annotation DB columns: ", paste(colnames(anno), collapse = ", "))
  message("Normalized columns: ", paste(normalize_colname(colnames(anno)), collapse = ", "))

  dr_symbol_candidates <- c(
    "dr_symbol", "dr_gene_symbol", "drerio_symbol", "zebrafish_symbol",
    "dre_symbol", "gene_symbol_dr", "gene_symbol_zebrafish", "gene_symbol",
    "drgenesymbol", "dr_gene_symbol"
  )
  hs_entrez_candidates <- c(
    "human_entrez", "human_entrezid", "hs_entrez", "hs_entrezid",
    "entrez_human", "entrezid_human", "hsa_entrez", "hsa_entrezid",
    "hsentrezid"
  )

  if (!is.null(dr_symbol_col_arg)) {
    if (!dr_symbol_col_arg %in% colnames(anno)) {
      die("--dr_symbol_col not found in annotation DB: ", dr_symbol_col_arg)
    }
    dr_symbol_col <- dr_symbol_col_arg
  } else {
    dr_symbol_col <- find_column(
      anno,
      dr_symbol_candidates,
      TRUE,
      "zebrafish SYMBOL column"
    )
  }

  if (!is.null(hs_entrez_col_arg)) {
    if (!hs_entrez_col_arg %in% colnames(anno)) {
      die("--hs_entrez_col not found in annotation DB: ", hs_entrez_col_arg)
    }
    hs_entrez_col <- hs_entrez_col_arg
  } else {
    hs_entrez_col <- find_column(
      anno,
      hs_entrez_candidates,
      TRUE,
      "human ENTREZID column"
    )
  }

  anno[[dr_symbol_col]] <- trimws(as.character(anno[[dr_symbol_col]]))
  anno[[hs_entrez_col]] <- trimws(as.character(anno[[hs_entrez_col]]))

  anno <- anno[anno[[dr_symbol_col]] != "" & !is.na(anno[[dr_symbol_col]]), , drop = FALSE]
  anno <- anno[anno[[hs_entrez_col]] != "" & !is.na(anno[[hs_entrez_col]]), , drop = FALSE]

  anno$dr_symbol_norm <- toupper(anno[[dr_symbol_col]])
  anno$hs_entrez_norm <- anno[[hs_entrez_col]]

  list(
    table = anno,
    dr_symbol_col = dr_symbol_col,
    hs_entrez_col = hs_entrez_col
  )
}

convert_dr_symbol_to_human_entrez <- function(symbols, anno_obj) {
  if (length(symbols) == 0) return(character(0))
  key <- toupper(trimws(as.character(symbols)))
  key <- key[key != "" & !is.na(key)]
  if (length(key) == 0) return(character(0))

  hits <- anno_obj$table$hs_entrez_norm[anno_obj$table$dr_symbol_norm %in% key]
  unique(hits[!is.na(hits) & hits != ""])
}

# ==================================
# 2. 读取DEG文件（上调和下调）
# ==================================
message("[1/5] Read input ...")
up_files <- list.files(
  path = deg_dir,
  pattern = pattern_up,
  full.names = TRUE,
  recursive = TRUE
)

down_files <- list.files(
  path = deg_dir,
  pattern = pattern_down,
  full.names = TRUE,
  recursive = TRUE
)

if (length(up_files) == 0) {
  stop("No DEG up files found")
}

if (length(down_files) == 0) {
  stop("No DEG down files found")
}

list_up <- lapply(up_files, read.csv)
list_down <- lapply(down_files, read.csv)

# ==================================
# 3. 提取gene symbol并转换为Entrez ID
# ==================================
out_up   <- sub("\\.csv$", "_symbols.txt", up_files)
out_down <- sub("\\.csv$", "_symbols.txt", down_files)

list_up_symbols   <- mapply(extract_symbol, list_up,   out_up,   SIMPLIFY = FALSE)
list_down_symbols <- mapply(extract_symbol, list_down, out_down, SIMPLIFY = FALSE)

names(list_up_symbols) <- sub("\\.csv$", "", basename(up_files))
names(list_down_symbols) <- sub("\\.csv$", "", basename(down_files))
if (species == "human") {
  message("[2/5] Map zebrafish SYMBOL to human ENTREZID using local annotation DB ...")
  anno_obj <- read_lab_annotation_db(
    annotation_db,
    dr_symbol_col_arg = dr_symbol_col_arg,
    hs_entrez_col_arg = hs_entrez_col_arg
  )
  message("Use columns: ", anno_obj$dr_symbol_col, " -> ", anno_obj$hs_entrez_col)

  entrez_up   <- lapply(list_up_symbols, convert_dr_symbol_to_human_entrez, anno_obj = anno_obj)
  entrez_down <- lapply(list_down_symbols, convert_dr_symbol_to_human_entrez, anno_obj = anno_obj)
  enrich_orgdb <- org.Hs.eg.db
  kegg_organism <- "hsa"

} else if (species == "zebrafish") {
  message("[2/5] Map zebrafish SYMBOL to zebrafish ENTREZID using org.Dr.eg.db ...")
  OrgDb <- org.Dr.eg.db 
  entrez_up   <- lapply(list_up_symbols,   convert_to_entrez, OrgDb = OrgDb)
  entrez_down <- lapply(list_down_symbols, convert_to_entrez, OrgDb = OrgDb)
  enrich_orgdb <- org.Dr.eg.db
  kegg_organism <- "dre"
  
}else {
  
  stop("Please set species as zebrafish or human")
  
}

# 输出 ENTREZ ID 结果
count_entrez_ids <- function(x) {
  x <- as.character(unlist(x, use.names = FALSE))
  x <- trimws(x)
  x <- x[!is.na(x) & x != ""]
  length(unique(x))
}

log_entrez_counts <- function(entrez_list, tag = "") {
  if (length(entrez_list) == 0) {
    message("[", tag, "] No groups found")
    return(invisible(NULL))
  }
  for (nm in names(entrez_list)) {
    n_ids <- count_entrez_ids(entrez_list[[nm]])
    message("[", tag, "] ", nm, ": ", n_ids, " mapped ENTREZID(s)")
  }
  invisible(NULL)
}

write_entrez <- function(entrez_list, files) {
  out_files <- sub("\\.csv$", "_entrez.txt", files)
  invisible(mapply(function(x, f) {
    write.table(unique(x), file = f, quote = FALSE, row.names = FALSE, col.names = FALSE)
  }, entrez_list, out_files))
}

log_entrez_counts(entrez_up, tag = "ENTREZ up")
log_entrez_counts(entrez_down, tag = "ENTREZ down")
write_entrez(entrez_up, up_files)
write_entrez(entrez_down, down_files)
message("[3/5] Entrez ID conversion done.")

# ==================================
# 4. GO / KEGG 富集分析
# ==================================
clean_entrez_ids <- function(x) {
  x <- as.character(unlist(x, use.names = FALSE))
  x <- trimws(x)
  x <- x[!is.na(x) & x != ""]
  unique(x)
}

run_enrich_go <- function(entrez_ids, OrgDb) {
  if (length(entrez_ids) == 0) return(data.frame())
  ego <- enrichGO(
    gene          = entrez_ids,
    OrgDb         = OrgDb,
    keyType       = "ENTREZID",
    ont           = "BP",
    pAdjustMethod = "BH",
    pvalueCutoff  = 0.05,
    qvalueCutoff  = 0.05
  )
  as.data.frame(ego)
}

run_enrich_kegg <- function(entrez_ids, organism) {
  if (length(entrez_ids) == 0) return(data.frame())
  ekegg <- enrichKEGG(
    gene         = entrez_ids,
    organism     = organism,
    pvalueCutoff = 0.05
  )
  as.data.frame(ekegg)
}

message("[4/5] Run GO/KEGG enrichment ...")
extract_group_name <- function(x) {
  sub("\\.DEG_(up|down)$", "", x, ignore.case = TRUE)
}

run_group_enrichment <- function(entrez_list, mode = c("GO", "KEGG"), OrgDb = NULL, organism = NULL) {
  mode <- match.arg(mode)
  out <- list()

  emit_enrich_log <- function(txt) {
    message(txt)
    cat(txt, "\n", sep = "")
    dbg <- file.path(outdir, "GK_enrichment_debug.log")
    cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " ", txt, "\n", sep = "", file = dbg, append = TRUE)
  }

  group_names <- names(entrez_list)
  if (is.null(group_names)) group_names <- rep("", length(entrez_list))
  if (any(is.na(group_names) | group_names == "")) {
    fallback_idx <- which(is.na(group_names) | group_names == "")
    group_names[fallback_idx] <- paste0("group_", fallback_idx)
  }

  emit_enrich_log(paste0("[", mode, "] groups to process: ", length(entrez_list)))

  for (i in seq_along(entrez_list)) {
    nm <- group_names[i]
    ids <- clean_entrez_ids(entrez_list[[i]])
    emit_enrich_log(paste0("[", mode, "] ", nm, ": ", length(ids), " ENTREZID(s) prepared for enrichment"))
    if (length(ids) == 0) {
      message("Skip ", nm, ": no ENTREZ ID")
      next
    }

    one <- if (mode == "GO") {
      run_enrich_go(ids, OrgDb = OrgDb)
    } else {
      run_enrich_kegg(ids, organism = organism)
    }

    if (nrow(one) == 0) {
      message("No ", mode, " terms for ", nm)
      next
    }

    one$group <- extract_group_name(nm)
    one$source_file <- nm
    out[[nm]] <- one
  }

  if (length(out) == 0) return(data.frame())
  do.call(rbind, out)
}

up_go <- run_group_enrichment(entrez_up, mode = "GO", OrgDb = enrich_orgdb)
down_go <- run_group_enrichment(entrez_down, mode = "GO", OrgDb = enrich_orgdb)
up_kegg <- run_group_enrichment(entrez_up, mode = "KEGG", organism = kegg_organism)
down_kegg <- run_group_enrichment(entrez_down, mode = "KEGG", organism = kegg_organism)

write.csv(up_go, file.path(outdir, "up_go.csv"), row.names = FALSE)
write.csv(down_go, file.path(outdir, "down_go.csv"), row.names = FALSE)
write.csv(up_kegg, file.path(outdir, "up_kegg.csv"), row.names = FALSE)
write.csv(down_kegg, file.path(outdir, "down_kegg.csv"), row.names = FALSE)
message("[5/5] Enrichment done. Results saved to: ", outdir)

