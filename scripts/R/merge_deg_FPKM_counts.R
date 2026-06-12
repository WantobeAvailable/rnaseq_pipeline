# 合并all_DEG_results.csv和merged_final.csv

library(data.table)

deg <- fread("all_DEG_results.csv")
merged <- fread("merged_final.csv")

deg[, gene_key := sub("\\|.*$", "", gene_id)]

merged[, gene_key := gene_id]

final_merged <- merge(
  merged,
  deg,
  by = "gene_key",
  all.x = TRUE,
  allow.cartesian = TRUE
)

fwrite(final_merged, "merged_final_with_DEG.csv")


