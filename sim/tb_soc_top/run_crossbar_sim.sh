#!/bin/bash
# ============================================================
# run_crossbar_sim.sh
# Run the AXI crossbar standalone simulation with VCS.
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOC_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

WORK_DIR="${SCRIPT_DIR}/work"
mkdir -p "${WORK_DIR}"

# Source Synopsys environment
if [ -f /home/anokyai/synopsys/env.sh ]; then
    source /home/anokyai/synopsys/env.sh
fi

# RTL file list
RTL_FILES=(
    "${SOC_ROOT}/hdl/soc/address_map.svh"
    "${SOC_ROOT}/hdl/soc/axi_crossbar.sv"
    "${SOC_ROOT}/hdl/soc/axi_ram_slave.sv"
)

TB_TOP="tb_axi_crossbar"
TB_FILE="${SCRIPT_DIR}/tb_axi_crossbar.sv"

echo "============================================"
echo " Compiling AXI Crossbar Simulation"
echo "============================================"

cd "${WORK_DIR}"

# Compile
vcs -full64 -sverilog -timescale=1ns/1ps \
    +v2k \
    -l comp.log \
    -top ${TB_TOP} \
    +incdir+"${SOC_ROOT}" \
    "${RTL_FILES[@]}" \
    "${TB_FILE}"

if [ $? -ne 0 ]; then
    echo "ERROR: Compilation failed. See ${WORK_DIR}/comp.log"
    exit 1
fi

echo ""
echo "============================================"
echo " Running Simulation"
echo "============================================"

./simv -l sim.log

echo ""
echo "Simulation complete. See ${WORK_DIR}/sim.log"
