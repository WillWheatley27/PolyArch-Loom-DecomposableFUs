#!/usr/bin/env bash
set -euo pipefail
cd /edata1/will/Decomposable_FU/synth
module load synopsys/syn/Y-2026.03-SP1
export SNPS_CONTAINER_BIND=/mnt/nas0,/edata1
dc_shell -f syn_tier_ladders.tcl 2>&1 | tee dc_tier_ladders.log
