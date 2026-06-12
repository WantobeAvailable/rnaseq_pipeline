#!/usr/bin/env bash
set -euo pipefail
source config/configuration.txt


while IFS=$'\t' read -r sample _; do
  [[ "$sample" == "sample" ]] && continue
  [[ -z "$sample" ]] && continue

  bam="${BAM_DIR}/${sample}.sorted.bam"
  prefix="${RSEQC_DIR}/${sample}_geneBody"
  out_txt="${prefix}.geneBodyCoverage.txt"
  log="${LOG_DIR}/${sample}.geneBody.log"

  if [[ -s "$out_txt" ]]; then
    echo "[skip] RSeQC exists: $sample"
    continue
  fi

  [[ -s "$bam" ]] || { echo "[ERROR] missing BAM for $sample: $bam" >&2; exit 1; }

  echo "[run] RSeQC geneBody: $sample"
  geneBody_coverage.py -r "$RSEQC_BED" -i "$bam" -o "$prefix" > "$log" 2>&1

done < "$SAMPLES"

echo "[run] plot_all_geneBody.R ..."
cd "$RSEQC_DIR"
Rscript ../scripts/R/plot_all_geneBody.R \
  --meta ../"$META" \
> ../"$LOG_DIR"/plot_geneBody.log 2>&1
cd ..
echo "[done] plot_all_geneBody.R finished"
