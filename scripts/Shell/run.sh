#!/bin/bash
#This batch was created to control the run order of batches in this pipeline.
set -euxo pipefail
source config/configuration.txt

mkdir -p "$BAM_DIR" "$LOG_DIR" "$RSEQC_DIR" "$ST_DIR" "$COUNT_DIR" "$FPKM_DIR"
#Defining three major functions in this pipeline.
function upstream(){
    echo "Start to run ta_IndexBuilding.sh..."
	bash scripts/Shell/ta_IndexBuilding.sh
	echo "ta_IndexBuilding.sh finished,run the next batch..."	
	
    echo "Start to run tb_Align.sh..."
	bash scripts/Shell/tb_Align.sh 
	echo "tb_Align.sh finished,run the next batch..."

    echo "Start to run tc_Samtools.sh..."
	bash scripts/Shell/tc_Samtools.sh
	echo "tc_Samtools.sh finished,run the next batch..."

    echo "Start to run td_Rseqc.sh..."
	bash scripts/Shell/td_Rseqc.sh
	echo "td_Rseqc.sh finished,run the next batch..."

    echo "Start to run te_Stringtie.sh..."
	bash scripts/Shell/te_Stringtie.sh
	echo "te_Stringtie.sh finished,run the next batch..."

	echo "Start to run tf_prepDE.sh..."
	bash scripts/Shell/tf_prepDE.sh		
	echo "tf_prepDE.sh finished,all batches in this pipeline have been completed!"
}

function counts_branch(){

	echo "Start to run tx_DEGanalysis.sh"
	bash scripts/Shell/tx_DEGanalysis.sh
	echo "tx_DEGanalysis.sh finished,run the next batch..."

	echo "Start to run tx_Volcano.sh..."
	bash scripts/Shell/tx_Volcano.sh
	echo "tx_Volcano.sh finished,run the next batch..."	

	echo "Start to run tx_GKenrichment.sh..."
	bash scripts/Shell/tx_GKenrichment.sh
	echo "tx_GKenrichment.sh finished,run the next batch..."

	echo "Start to run  tx_GKplot.sh..."
	bash scripts/Shell/tx_GKplot.sh
	echo "tx_GKplot.sh finished,run the next batch..."	

}

function fpkm_branch(){
	echo "Start to run ty_preprocess_fpkm.sh..."
	bash scripts/Shell/ty_preprocess_fpkm.sh
	echo "ty_preprocess_fpkm.sh finished,run the next batch..."

	if [[ "${DO_COMBAT}" == "1" ]]; then
	echo "Start to run ty_BatchCorrecting.sh..."
	bash scripts/Shell/ty_BatchCorrecting.sh
	echo "ty_BatchCorrecting.sh finished,run the next batch..."
	else
    echo "[skip] batch correcting (ComBat) disabled (DO_COMBAT=0)"
    fi

	echo "Start to run ty_PCA.sh..."
	bash scripts/Shell/ty_PCA.sh
	echo "ty_PCA.sh finished,run the next batch..."	

	echo "Start to run  ty_Heatmap.sh..."
	bash scripts/Shell/ty_Heatmap.sh
	echo "ty_Heatmap.sh finished,all drawing batches in this pipeline have been completed!"	
}

upstream
counts_branch
fpkm_branch

exit 0
