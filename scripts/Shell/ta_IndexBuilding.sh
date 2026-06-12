#!/usr/bin/env bash
set -euxo pipefail
source config/configuration.txt

# 取出HISAT2_INDEX_PREFIX的“目录部分”并创建目录
mkdir -p "$(dirname "$HISAT2_INDEX_PREFIX")" 
# 避免重复建索引
if ls "${HISAT2_INDEX_PREFIX}".*.ht2 >/dev/null 2>&1; then
  echo "[skip] HISAT2 index exists"
  exit 0
fi

hisat2_extract_splice_sites.py "$REF_GTF" > "$REF_DIR"/splice_sites.txt
hisat2_extract_exons.py        "$REF_GTF" > "$REF_DIR"/exons.txt

hisat2-build \
  --ss "$REF_DIR"/splice_sites.txt \
  --exon "$REF_DIR"/exons.txt \
  "$REF_GENOME" \
  "$HISAT2_INDEX_PREFIX"
