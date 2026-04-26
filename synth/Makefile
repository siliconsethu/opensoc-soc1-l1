##############################################################################
# synth/Makefile  —  Synthesis build system
#                    OpenSoC Tier-1 Shakti E-class SoC
#
# USAGE
#   make -f synth/Makefile <target>
#   (run from the repository root, not from synth/)
#
# TARGETS
#   genus_l1        ASIC synthesis, Level-1 (sky130, 4 KB SRAM)
#   genus_l2        ASIC synthesis, Level-2 (sky130, 128 KB SRAM + Boot ROM)
#   vivado_synth    FPGA synthesis only (Vivado, no implementation)
#   vivado_impl     FPGA synthesis + place + route (no bitstream)
#   vivado_bit      Full Vivado flow including bitstream
#   vivado_l2       Full Vivado flow for Level-2
#   gen_sram_lib    Generate sky130 SRAM Liberty model via OpenRAM
#   reports         Print latest QoR summary from log files
#   clean_genus     Delete Genus outputs
#   clean_vivado    Delete Vivado outputs
#   clean           Delete all synthesis outputs
#
# ENVIRONMENT VARIABLES (export before make, or override on command line)
#   PDK_ROOT    sky130A PDK root (default: /opt/pdk/sky130A)
#   GENUS       Genus executable  (default: genus)
#   VIVADO      Vivado executable (default: vivado)
#   PART        Xilinx FPGA part  (default: xc7a35tcpg236-1 = Basys3)
#               Arty A7-35: xc7a35tcsg324-1
#               Nexys A7  : xc7a50tcsg324-1
#
# EXAMPLE
#   export PDK_ROOT=/opt/pdk/sky130A
#   export PART=xc7a35tcsg324-1        # Arty A7-35
#   make -f synth/Makefile genus_l1
#   make -f synth/Makefile vivado_bit
##############################################################################

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
PDK_ROOT   ?= /opt/pdk/sky130A
GENUS      ?= genus
VIVADO     ?= vivado
PART       ?= xc7a35tcpg236-1

DESIGN_ROOT := $(shell pwd)
SYNTH_DIR   := $(DESIGN_ROOT)/synth
SCRIPTS_DIR := $(SYNTH_DIR)/scripts
CONST_DIR   := $(SYNTH_DIR)/constraints
OUT_GENUS   := $(SYNTH_DIR)/out/genus
OUT_VIVADO  := $(SYNTH_DIR)/out/vivado

# Export variables so sub-scripts (TCL) can read them
export PDK_ROOT DESIGN_ROOT PART

# ---------------------------------------------------------------------------
# ASIC — Cadence Genus + sky130
# ---------------------------------------------------------------------------

.PHONY: genus_l1
genus_l1: $(OUT_GENUS)/reports/timing_setup.rpt
	@echo ""
	@echo "================================================"
	@echo "  GENUS L1 synthesis complete"
	@echo "  Netlist : $(OUT_GENUS)/netlists/t1_soc_top_eclass_netlist.v"
	@echo "  Reports : $(OUT_GENUS)/reports/"
	@echo "================================================"

$(OUT_GENUS)/reports/timing_setup.rpt: \
		$(SYNTH_DIR)/rtl/t1_sram_sky130_wrap.sv \
		$(SYNTH_DIR)/scripts/genus/genus_run.tcl \
		$(CONST_DIR)/t1_soc_top_eclass.sdc \
		$(CONST_DIR)/exceptions.sdc
	@mkdir -p $(OUT_GENUS)/reports $(OUT_GENUS)/netlists $(OUT_GENUS)/db
	@echo "------------------------------------------"
	@echo "  GENUS L1: ASIC synthesis (sky130, 25 MHz)"
	@echo "------------------------------------------"
	DESIGN_ROOT=$(DESIGN_ROOT) \
	PDK_ROOT=$(PDK_ROOT) \
	WORK_DIR=$(OUT_GENUS) \
	LEVEL=1 \
	$(GENUS) -no_gui -execute $(SCRIPTS_DIR)/genus/genus_run.tcl \
	    2>&1 | tee $(OUT_GENUS)/genus_l1.log
	@grep -E "WNS|Area|ERROR|WARNING" $(OUT_GENUS)/genus_l1.log | tail -20

.PHONY: genus_l2
genus_l2:
	@mkdir -p $(OUT_GENUS)/reports $(OUT_GENUS)/netlists $(OUT_GENUS)/db
	@echo "------------------------------------------"
	@echo "  GENUS L2: ASIC synthesis (sky130, 25 MHz)"
	@echo "------------------------------------------"
	DESIGN_ROOT=$(DESIGN_ROOT) \
	PDK_ROOT=$(PDK_ROOT) \
	WORK_DIR=$(OUT_GENUS) \
	LEVEL=2 \
	$(GENUS) -no_gui -execute $(SCRIPTS_DIR)/genus/genus_run.tcl \
	    2>&1 | tee $(OUT_GENUS)/genus_l2.log
	@grep -E "WNS|Area|ERROR|WARNING" $(OUT_GENUS)/genus_l2.log | tail -20

# ---------------------------------------------------------------------------
# ASIC — Generate sky130 SRAM Liberty model (requires OpenRAM)
# ---------------------------------------------------------------------------
SRAM_LIB  := $(SYNTH_DIR)/libs/sky130_sram_1rw1r_32x1024_8.lib
SRAM_CFG  := $(SYNTH_DIR)/libs/sky130_sram_1rw1r_32x1024_8.cfg

.PHONY: gen_sram_lib
gen_sram_lib: $(SRAM_LIB)

$(SRAM_LIB): $(SRAM_CFG)
	@echo "Generating sky130 SRAM Liberty via OpenRAM..."
	openram $(SRAM_CFG)
	@cp sky130_sram_1rw1r_32x1024_8/sky130_sram_1rw1r_32x1024_8.lib $(SYNTH_DIR)/libs/
	@echo "SRAM Liberty written to $(SRAM_LIB)"

# Write default OpenRAM config if not present
$(SRAM_CFG):
	@mkdir -p $(SYNTH_DIR)/libs
	@echo "# OpenRAM config for sky130 1024x32 SRAM"           > $@
	@echo "word_size = 32"                                      >> $@
	@echo "num_words = 1024"                                    >> $@
	@echo "num_banks = 1"                                       >> $@
	@echo "tech_name = sky130"                                  >> $@
	@echo "nominal_corner_only = True"                          >> $@
	@echo "output_name = sky130_sram_1rw1r_32x1024_8"          >> $@
	@echo "output_path = sky130_sram_1rw1r_32x1024_8/"         >> $@
	@echo "OpenRAM config written to $@"
	@echo "Edit as needed, then run: make gen_sram_lib"

# ---------------------------------------------------------------------------
# FPGA — Xilinx Vivado
# ---------------------------------------------------------------------------

.PHONY: vivado_synth
vivado_synth:
	@mkdir -p $(OUT_VIVADO)/reports $(OUT_VIVADO)/checkpoints $(OUT_VIVADO)/bitstream
	@echo "------------------------------------------"
	@echo "  VIVADO L1: synthesis only"
	@echo "------------------------------------------"
	DESIGN_ROOT=$(DESIGN_ROOT) \
	WORK_DIR=$(OUT_VIVADO) \
	PART=$(PART) \
	LEVEL=1 \
	$(VIVADO) -mode batch \
	    -source $(SCRIPTS_DIR)/vivado/vivado_run.tcl \
	    -tclargs synth_only \
	    2>&1 | tee $(OUT_VIVADO)/vivado_synth_l1.log
	@grep -E "WNS|Timing|ERROR|WARNING|CRITICAL" \
	    $(OUT_VIVADO)/vivado_synth_l1.log | tail -20

.PHONY: vivado_impl
vivado_impl:
	@mkdir -p $(OUT_VIVADO)/reports $(OUT_VIVADO)/checkpoints $(OUT_VIVADO)/bitstream
	@echo "------------------------------------------"
	@echo "  VIVADO L1: synthesis + place + route"
	@echo "------------------------------------------"
	DESIGN_ROOT=$(DESIGN_ROOT) \
	WORK_DIR=$(OUT_VIVADO) \
	PART=$(PART) \
	LEVEL=1 \
	$(VIVADO) -mode batch \
	    -source $(SCRIPTS_DIR)/vivado/vivado_run.tcl \
	    2>&1 | tee $(OUT_VIVADO)/vivado_impl_l1.log
	@grep -E "WNS|Timing|ERROR|WARNING|CRITICAL|complete" \
	    $(OUT_VIVADO)/vivado_impl_l1.log | tail -20

.PHONY: vivado_bit
vivado_bit: vivado_impl
	@echo ""
	@echo "================================================"
	@echo "  Bitstream: $(OUT_VIVADO)/bitstream/t1_soc_top_eclass_l1.bit"
	@echo "  Program:   make -f synth/Makefile program"
	@echo "================================================"

.PHONY: vivado_l2
vivado_l2:
	@mkdir -p $(OUT_VIVADO)/reports $(OUT_VIVADO)/checkpoints $(OUT_VIVADO)/bitstream
	@echo "------------------------------------------"
	@echo "  VIVADO L2: full flow"
	@echo "------------------------------------------"
	DESIGN_ROOT=$(DESIGN_ROOT) \
	WORK_DIR=$(OUT_VIVADO) \
	PART=$(PART) \
	LEVEL=2 \
	$(VIVADO) -mode batch \
	    -source $(SCRIPTS_DIR)/vivado/vivado_run.tcl \
	    2>&1 | tee $(OUT_VIVADO)/vivado_impl_l2.log

# ---------------------------------------------------------------------------
# FPGA Programming (requires board connected and Vivado hw_server running)
# ---------------------------------------------------------------------------
.PHONY: program
program: $(OUT_VIVADO)/bitstream/t1_soc_top_eclass_l1.bit
	$(VIVADO) -mode batch -source - <<'EOF'
	open_hw_manager
	connect_hw_server -allow_non_jtag
	open_hw_target
	current_hw_device [get_hw_devices xc7a35t_0]
	set_property PROGRAM.FILE {$(OUT_VIVADO)/bitstream/t1_soc_top_eclass_l1.bit} \
	    [get_hw_devices xc7a35t_0]
	program_hw_devices [get_hw_devices xc7a35t_0]
	close_hw_manager
	EOF

# ---------------------------------------------------------------------------
# Reports summary
# ---------------------------------------------------------------------------
.PHONY: reports
reports:
	@echo ""
	@echo "=== Genus L1 QoR ==="
	@if [ -f $(OUT_GENUS)/reports/timing_setup.rpt ]; then \
	    grep -E "WNS|Slack|Arrival" $(OUT_GENUS)/reports/timing_setup.rpt | head -5; \
	    grep -E "Total cell area|Combinational" $(OUT_GENUS)/reports/area.rpt | head -5; \
	else echo "  No Genus reports found. Run: make genus_l1"; fi
	@echo ""
	@echo "=== Vivado L1 QoR ==="
	@if [ -f $(OUT_VIVADO)/reports/post_route_timing.rpt ]; then \
	    grep -E "WNS|TNS|Design Timing" $(OUT_VIVADO)/reports/post_route_timing.rpt | head -5; \
	    grep -E "LUT|FF|BRAM" $(OUT_VIVADO)/reports/post_route_util.rpt | head -10; \
	else echo "  No Vivado reports found. Run: make vivado_bit"; fi

# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------
.PHONY: clean_genus
clean_genus:
	rm -rf $(OUT_GENUS) genus.log genus.cmd .cadence

.PHONY: clean_vivado
clean_vivado:
	rm -rf $(OUT_VIVADO) vivado.log vivado.jou *.str .Xil

.PHONY: clean
clean: clean_genus clean_vivado
	@echo "Synthesis outputs removed."

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
.PHONY: help
help:
	@echo ""
	@echo "  OpenSoC Tier-1 Synthesis Makefile"
	@echo ""
	@echo "  ASIC (Cadence Genus + SkyWater sky130):"
	@echo "    make -f synth/Makefile genus_l1    Level-1 (4 KB, 25 MHz)"
	@echo "    make -f synth/Makefile genus_l2    Level-2 (128 KB, 25 MHz)"
	@echo "    make -f synth/Makefile gen_sram_lib  Generate SRAM .lib via OpenRAM"
	@echo ""
	@echo "  FPGA (Xilinx Vivado, default: Basys3 xc7a35tcpg236-1):"
	@echo "    make -f synth/Makefile vivado_synth  Synthesis only"
	@echo "    make -f synth/Makefile vivado_impl   Synth + place + route"
	@echo "    make -f synth/Makefile vivado_bit    Full flow + bitstream"
	@echo "    make -f synth/Makefile program       Program connected board"
	@echo ""
	@echo "  Utility:"
	@echo "    make -f synth/Makefile reports       Print QoR summary"
	@echo "    make -f synth/Makefile clean         Remove all outputs"
	@echo ""
	@echo "  Variables (override on command line or export):"
	@echo "    PDK_ROOT=$(PDK_ROOT)"
	@echo "    PART=$(PART)"
	@echo "    GENUS=$(GENUS)"
	@echo "    VIVADO=$(VIVADO)"
