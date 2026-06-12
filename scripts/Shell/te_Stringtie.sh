#!/usr/bin/env bash
set -euo pipefail
source config/configuration.txt

while IFS=$'\t' read -r sample _; do
  [[ "$sample" == "sample" ]] && continue
  [[ -z "$sample" ]] && continue

  bam="${BAM_DIR}/${sample}.sorted.bam"
  out_gtf="${ST_DIR}/${sample}.gtf"
  out_abund="${FPKM_DIR}/${sample}.gene_abund.txt"
  log="${LOG_DIR}/${sample}.stringtie.log"

  if [[ -s "$out_gtf" && -s "$out_abund" ]]; then
    echo "[skip] StringTie exists: $sample"
    continue
  fi

  [[ -s "$bam" ]] || { echo "[ERROR] missing BAM for $sample: $bam" >&2; exit 1; }

  echo "[run] StringTie: $sample"
  stringtie "$bam" \
    -G "$STRINGTIE_GTF" \
    -o "$out_gtf" \
    -A "$out_abund" \
    -e -B \
    > "$log" 2>&1

done < "$SAMPLES"

echo "[run] merge_FPKM.r ..."                                    
cd "$FPKM_DIR"
Rscript ../scripts/R/merge_FPKM.r \
  --o merged_FPKM.csv \
  > ../"$LOG_DIR"/merge_FPKM.log 2>&1
cp merged_FPKM.csv ../"$COUNT_DIR"
cd ..
echo "[done] merge_FPKM.r finished"


