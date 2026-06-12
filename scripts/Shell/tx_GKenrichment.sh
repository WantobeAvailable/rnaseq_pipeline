#!/usr/bin/env bash
set -euxo pipefail
source config/configuration.txt


if [[ ! -d "$DEG_ROOT" ]]; then
  echo "[error] DEG root directory not found: $DEG_ROOT"
  exit 1
fi

echo "[run] GO/KEGG enrichment by R package (species=${SPECIES}) ..."
Rscript "$GK_SCRIPT" \
  --deg_dir "$DEG_ROOT" \
  --species "$SPECIES" \
  --pattern_up "$PATTERN_UP" \
  --pattern_down "$PATTERN_DOWN" \
  --annotation_db "$ANNOTATION_DB" \
  --dr_symbol_col "$GK_DR_SYMBOL_COL" \
  --hs_entrez_col "$GK_HS_ENTREZ_COL" \
  --outdir "$DEG_ROOT" \
  > "$LOG_DIR"/GK_enrichment_merged.log 2>&1

echo "[done] All GO/KEGG enrichment finished (merged output in $DEG_ROOT)"
