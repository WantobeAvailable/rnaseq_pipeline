#!/usr/bin/env bash
set -euxo pipefail
source configuration.txt

# 这个脚本需要根据实际分组情况更改参数
echo "[run] analyzing DEG with counts..."
cd "$COUNT_DIR"

if [[ ${#DEG_CONTRASTS[@]} -eq 0 ]]; then
  echo "[error] DEG_CONTRASTS is empty in configuration.txt"
  exit 1
fi

for spec in "${DEG_CONTRASTS[@]}"; do
  IFS='|' read -r FILTER_EXP DESIGN_VAR TREAT_GRP CONTROL_GRP OUTDIR PREFIX <<< "$spec"

  if [[ -z "$FILTER_EXP" || -z "$DESIGN_VAR" || -z "$TREAT_GRP" || -z "$CONTROL_GRP" || -z "$OUTDIR" || -z "$PREFIX" ]]; then
    echo "[error] Invalid DEG_CONTRASTS entry: $spec"
    exit 1
  fi

  echo "[run] DEG contrast: $PREFIX"
  Rscript ../scripts/DEG_run_one_contrast.R \
    --counts gene_count_matrix.csv \
    --meta ../"$META" \
    --filter "$FILTER_EXP" \
    --design "$DESIGN_VAR" \
    --treat "$TREAT_GRP" \
    --control "$CONTROL_GRP" \
    --outdir "$OUTDIR" \
    --prefix "$PREFIX" \
    --lfc "${DEG_LFC:-1.5}" \
    --p "${DEG_P:-0.05}" \
    --p_col "${DEG_P_COL:-padj}" \
    > ../"$LOG_DIR"/DEG_"$PREFIX".log 2>&1
done

cd ..
echo "[done] DEG analysis finished"