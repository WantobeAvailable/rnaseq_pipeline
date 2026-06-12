#!/usr/bin/env bash
set -euo pipefail
source configuration.txt

# KEEP_SAM 由 configuration.txt 统一控制（true/false）

while IFS=$'\t' read -r sample _; do
  [[ "$sample" == "sample" ]] && continue
  [[ -z "$sample" ]] && continue

  sam="${BAM_DIR}/${sample}.sam"
  bam="${BAM_DIR}/${sample}.sorted.bam"
  bai="${bam}.bai"

  if [[ -s "$bam" && -s "$bai" ]]; then
    echo "[skip] BAM exists: $sample"
    continue
  fi

  [[ -s "$sam" ]] || { echo "[ERROR] missing SAM for $sample: $sam" >&2; exit 1; }

  echo "[run] samtools  convert/sort/index: $sample"
  # 把 SAM 转换为 BAM 并排序
  samtools view -@ "$THREADS" -bS "$sam" \
    | samtools sort -@ "$THREADS" -o "$bam" -
  # 为排序后的 BAM 建索引
  samtools index "$bam"

  if [[ "$KEEP_SAM" != "true" ]]; then
    rm -f "$sam"
  fi

done < "$SAMPLES"
