#!/usr/bin/env bash
set -euxo pipefail
source configuration.txt

# 需要准备GO term 分组表
echo "[run]  Plot GO results..."
Rscript scripts/plot_GO.R \
  --indir "${COUNT_DIR}" \
  --up_go "${COUNT_DIR}"/up_go.csv \
  --down_go "${COUNT_DIR}"/down_go.csv \
  --significance "${GKPLOT_SIGNIFICANCE}" \
  --go_map "${COUNT_DIR}"/go_modules.tsv \
  > "$LOG_DIR"/GO.log 2>&1
echo "[done] GO plotting finished."

# 需要挑选KEGG pathway 
echo "[run]  Plot KEGG results..."
Rscript scripts/plot_KEGG.R \
  --indir "${COUNT_DIR}" \
  --up_kegg "${COUNT_DIR}"/up_kegg.csv \
  --down_kegg "${COUNT_DIR}"/down_kegg.csv \
  --significance "${GKPLOT_SIGNIFICANCE}" \
  --pathways "${COUNT_DIR}"/kegg_pathways.txt \
  > "$LOG_DIR"/KEGG.log 2>&1
echo "[done] KEGG plotting finished."
