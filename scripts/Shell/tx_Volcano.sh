#!/usr/bin/env bash
set -euxo pipefail
source config/configuration.txt

echo "[run] drawing Volcano with FPKM..."

mapfile -t DEG_ALL_FILES < <(find "$COUNT_DIR/DEG" -type f -name "*.DEG_all.csv" | sort)

if [[ ${#DEG_ALL_FILES[@]} -eq 0 ]]; then
  echo "[warn] No *.DEG_all.csv found under $COUNT_DIR/DEG"
  exit 0
fi

VOLCANO_LFC="${VOLCANO_LFC:-1.5}"
VOLCANO_P="${VOLCANO_P:-0.05}"
VOLCANO_P_COL="${VOLCANO_P_COL:-padj}"
VOLCANO_TITLE_SUFFIX="${VOLCANO_TITLE_SUFFIX:-Volcano Plot}"

: > "$LOG_DIR"/Volcano_analysis.log
for deg_fp in "${DEG_ALL_FILES[@]}"; do
  base_name=$(basename "$deg_fp")
  prefix_name="${base_name%.DEG_all.csv}"
  out_prefix="$COUNT_DIR/${prefix_name}_Volcano"
  plot_title="${prefix_name} ${VOLCANO_TITLE_SUFFIX}"

  echo "[run] Volcano: $prefix_name"
  Rscript scripts/R/Volcano_analysis.R \
    --deg "$deg_fp" \
    --prefix "$out_prefix" \
    --lfc "$VOLCANO_LFC" \
    --p "$VOLCANO_P" \
    --p_col "$VOLCANO_P_COL" \
    --title "$plot_title" \
    >> "$LOG_DIR"/Volcano_analysis.log 2>&1
done

echo "[done] Volcano analysis finished"
