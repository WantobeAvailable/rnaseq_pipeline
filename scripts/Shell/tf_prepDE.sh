#!/usr/bin/env bash
set -euxo pipefail
source config/configuration.txt

sample_lst="sample_lst.txt"
gene_out="${COUNT_DIR}/gene_count_matrix.csv"
tx_out="${COUNT_DIR}/transcript_count_matrix.csv"

if [[ -s "$gene_out" && -s "$tx_out" ]]; then
  echo "[skip] prepDE outputs exist"
  exit 0
fi

: > "$sample_lst"
while IFS=$'\t' read -r sample _; do
  [[ "$sample" == "sample" ]] && continue
  [[ -z "$sample" ]] && continue
  echo -e "${sample}\t$(pwd)/${ST_DIR}/${sample}.gtf" >> "$sample_lst"
done < "$SAMPLES"

python3 "$PREPDE" \
  -i "$sample_lst" \
  -g "$gene_out" \
  -t "$tx_out"

export R_BACKTRACE_ON_ERROR=numbered
export R_KEEP_PKG_SOURCE=yes
echo "[run] merging FPKM and counts..."
cd "$COUNT_DIR"
Rscript ../scripts/R/fix_FPKM.R \
  --fpkm merged_FPKM.csv \
  --counts gene_count_matrix.csv \
  --out_fix merged_FPKM_fixed.csv \
  --out_unfix FPKM_unfixed.csv \
 > ../"$LOG_DIR"/fix_FPKM.log 2>&1
cp merged_FPKM_fixed.csv ../"$FPKM_DIR"
cp FPKM_unfixed.csv ../"$FPKM_DIR"
Rscript ../scripts/R/merge_FPKM_counts.R \
  --fpkm merged_FPKM_fixed.csv \
  --counts gene_count_matrix.csv \
  --out merged_FPKM_count.csv \
> ../"$LOG_DIR"/merge_FPKM_counts.log 2>&1
cd ..
echo "[done] merged FPKM and counts"
