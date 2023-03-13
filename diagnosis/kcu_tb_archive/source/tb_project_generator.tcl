# In the source directory run the below command
# vivado -nojournal -nolog -mode batch -source tb_project_generator.tcl

# Environment variables
set FPGA_TYPE xcku040-ffva1156-2-e

# Generate ip
set argv $FPGA_TYPE
set argc 1
source ip_generator.tcl

# Create project
create_project tb_project ../tb_project -part $FPGA_TYPE -force
set_property target_language VHDL [current_project]
set_property target_simulator XSim [current_project]

# Add testbench files
add_files -norecurse "Firmware_pkg.vhd Firmware_tb.vhd ../ip/$FPGA_TYPE/clockManager/clockManager.xci ../ip/$FPGA_TYPE/ila/ila.xci ../ip/$FPGA_TYPE/lut_input1/lut_input1.xci ../ip/$FPGA_TYPE/lut_input2/lut_input2.xci ../ip/$FPGA_TYPE/vio_input/vio_input.xci ../ip/$FPGA_TYPE/spi_readback_fifo/spi_readback_fifo.xci ../ip/$FPGA_TYPE/spi_cmd_fifo/spi_cmd_fifo.xci ../ip/$FPGA_TYPE/writeSpiFIFO/writeSpiFIFO.xci"
add_files "vme/"
add_files "dcfeb/"
add_files -fileset constrs_1 -norecurse "Firmware_tb.xdc"

# Add ODMB source code
add_files "../../source/"

# Add tcl for simulation
set_property -name {xsim.simulate.custom_tcl} -value {../../../../source/Firmware_tb.tcl} -objects [get_filesets sim_1]

# add_files -norecurse "../tb_project/cfebjtag_tb_behav.wcfg"
set_property SOURCE_SET sources_1 [get_filesets sim_1]
add_files -fileset sim_1 -norecurse {../diagnose/cfebjtag_tb_behav.wcfg ../diagnose/vme_master_behav.wcfg}
# set_property xsim.view {my_tb_behav.wcfg my_tb_behav_1.wcfg my_tb_behav_2.wcfg} [get_filesets sim_1]

# Set test bench as top module
set_property top Firmware_tb [get_filesets sources_1]
set_property top Firmware_tb [get_filesets sim_1]

# Set ip as global
set_property generate_synth_checkpoint false [get_files  ../ip/$FPGA_TYPE/clockManager/clockManager.xci]
set_property generate_synth_checkpoint false [get_files  ../ip/$FPGA_TYPE/ila/ila.xci]
set_property generate_synth_checkpoint false [get_files  ../ip/$FPGA_TYPE/lut_input1/lut_input1.xci]
set_property generate_synth_checkpoint false [get_files  ../ip/$FPGA_TYPE/lut_input2/lut_input2.xci]
set_property generate_synth_checkpoint false [get_files  ../ip/$FPGA_TYPE/vio_input/vio_input.xci]
set_property generate_synth_checkpoint false [get_files  ../ip/$FPGA_TYPE/spi_readback_fifo/spi_readback_fifo.xci]
set_property generate_synth_checkpoint false [get_files  ../ip/$FPGA_TYPE/spi_cmd_fifo/spi_cmd_fifo.xci]
set_property generate_synth_checkpoint false [get_files  ../ip/$FPGA_TYPE/writeSpiFIFO/writeSpiFIFO.xci]

puts "\[Success\] Created tb_project"
close_project
