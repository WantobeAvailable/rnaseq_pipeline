#!/usr/bin/env bash
set -euxo pipefail
source config/configuration.txt


# 循环读取SAMPLES_TSV的每一行,按 TSV（Tab 分隔）来拆列,依次赋值给变量 sample, fq1, fq2
while IFS=$'\t' read -r sample fq1 fq2; do
  # 去掉可能存在的行尾回车符
  fq2="${fq2%$'\r'}"  
  # 跳过表头行
  [[ "$sample" == "sample" ]] && continue
  # 跳过空行
  [[ -z "$sample" ]] && continue
  # 生成输出文件路径
  sam="${BAM_DIR}/${sample}.sam"
  log="${LOG_DIR}/${sample}.hisat2.log"
  # 如果 SAM 已经存在就跳过
  if [[ -s "$sam" ]]; then
    echo "[skip] SAM exists: $sample"
    continue
  fi
  # 检查$fq1 和 $fq2 两个文件是否都存在且非空
  [[ -s "$fq1" && -s "$fq2" ]] || { echo "[ERROR] missing FASTQ for $sample" >&2; exit 1; }

  echo "[run] hisat2 -> SAM: $sample"
  hisat2 -p "$THREADS" --dta -x "$HISAT2_INDEX_PREFIX" \
    -1 "$fq1" -2 "$fq2" \
    -S "$sam" \
    2> "$log"

done < "$SAMPLES"
