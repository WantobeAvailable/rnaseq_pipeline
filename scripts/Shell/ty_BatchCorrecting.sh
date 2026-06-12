#!/usr/bin/env bash
set -euxo pipefail
source configuration.txt

echo "[run] Correcting batch effects..."
Rscript scripts/correct_batch.R \
  --meta "$META" \
  --fpkm "$FPKM_DIR"/fpkm.preprocessed.numeric.csv \
  --batch_col "$BATCH_CORRECT_BATCH_COL" \
  --design "$BATCH_CORRECT_DESIGN" \
  --out "$FPKM_DIR"/fpkm.combat.csv \
> "$LOG_DIR"/correct_batch.log 2>&1
echo "[done] batch correction finished"