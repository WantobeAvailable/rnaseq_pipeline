#!/usr/bin/env bash
set -euxo pipefail
source configuration.txt

if [[ "${DO_COMBAT}" == "1" ]]; then
  PCA_IN="${FPKM_DIR}/fpkm.combat.csv"
else
  PCA_IN="${FPKM_DIR}/fpkm.preprocessed.numeric.csv"
fi

echo "[run] drawing PCA with FPKM..."
Rscript scripts/PCA_analysis.R \
  --meta "${META}" \
  --fpkm "${PCA_IN}" \
  --top_n "${PCA_TOP_N}" \
  --out_png PCA_batch.png \
  --out_scores PCA_scores_sd.csv \
  > "$LOG_DIR"/PCA_analysis.log 2>&1

echo "[done] PCA analysis finished"
