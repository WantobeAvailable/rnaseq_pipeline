#!/usr/bin/env bash
set -euxo pipefail
source config/configuration.txt

echo "[run] preparing FPKM matrix..."
Rscript scripts/R/preprocess_fpkm.R \
  --meta "$META" \
  --fpkm "$FPKM_DIR"/merged_FPKM_fixed.csv \
  --out_numeric "$FPKM_DIR"/fpkm.preprocessed.numeric.csv \
  --out_with_anno "$FPKM_DIR"/fpkm.preprocessed.with_anno.csv \
> "$LOG_DIR"/preprocess_fpkm.log 2>&1
echo "[done] preprocessing FPKM finished"
