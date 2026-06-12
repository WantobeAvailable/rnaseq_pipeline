#!/usr/bin/env bash
set -euxo pipefail
source config/configuration.txt


echo "[run] drawing Heatmap with FPKM..."
cmd=(
  Rscript scripts/R/heatmap2.R
  --meta "$META"
  --fpkm "$FPKM_DIR"/fpkm.preprocessed.numeric.csv
  --out "$FPKM_DIR"/heatmap
  --n_var "${HEATMAP_N_VAR:-200}"
)

# 可选：样本分组顺序
if [[ -n "${HEATMAP_GROUP_ORDER:-}" ]]; then
  cmd+=(--group_order "$HEATMAP_GROUP_ORDER")
fi

# 可选：module 模式
if [[ -n "${HEATMAP_MODULE_FILE:-}" ]]; then
  cmd+=(--module "$HEATMAP_MODULE_FILE")
else
  cmd+=(--module rawdata/gene_module.csv)
fi
if [[ -n "${HEATMAP_MODULE_ORDER:-}" ]]; then
  cmd+=(--module_order "$HEATMAP_MODULE_ORDER")
fi

# 可选：DEG 模式（需要 up/down 同时提供）
if [[ -n "${HEATMAP_DEG_UP:-}" && -n "${HEATMAP_DEG_DOWN:-}" ]]; then
  cmd+=(
    --deg_up "$HEATMAP_DEG_UP"
    --deg_down "$HEATMAP_DEG_DOWN"
    --n_deg "${HEATMAP_N_DEG:-100}"
  )
  if [[ -n "${HEATMAP_DEG_GROUPS:-}" ]]; then
    cmd+=(--deg_groups "$HEATMAP_DEG_GROUPS")
  fi
fi

"${cmd[@]}" > "$LOG_DIR"/heatmap.log 2>&1
echo "[done] Heatmap analysis finished"
