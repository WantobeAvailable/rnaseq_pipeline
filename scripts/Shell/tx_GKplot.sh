#!/usr/bin/env bash
set -euxo pipefail
source config/configuration.txt

# 需要准备GO term 分组表
echo "[run]  Plot GO results..."
Rscript scripts/R/plot_GO.R \
  --indir "${DEG_ROOT}" \
  --up_go "${DEG_ROOT}"/up_go.csv \
  --down_go "${DEG_ROOT}"/down_go.csv \
  --significance "${GKPLOT_SIGNIFICANCE}" \
  --go_map "${COUNT_DIR}"/go_modules.tsv \
  > "$LOG_DIR"/GO.log 2>&1
echo "[done] GO plotting finished."

# 需要挑选KEGG pathway 
echo "[run]  Plot KEGG results..."
Rscript scripts/R/plot_KEGG.R \
  --indir "${DEG_ROOT}" \
  --up_kegg "${DEG_ROOT}"/up_kegg.csv \
  --down_kegg "${DEG_ROOT}"/down_kegg.csv \
  --significance "${GKPLOT_SIGNIFICANCE}" \
  --pathways "${COUNT_DIR}"/kegg_pathways.txt \
  > "$LOG_DIR"/KEGG.log 2>&1
echo "[done] KEGG plotting finished."
