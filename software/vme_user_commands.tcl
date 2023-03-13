#run with vivado -nojournal -nolog -mode batch -notrace -source vme_user_commands.tcl
##test non-vivado commands with !/usr/bin/tclsh

#set input_file [open "vme_commands.txt" r]
#close $input_file

open_hw
connect_hw_server -url localhost:3121 
current_hw_target [get_hw_targets */xilinx_tcf/Digilent/210308AB0E6E]
set_property PARAM.FREQUENCY 15000000 [get_hw_targets */xilinx_tcf/Digilent/210308AB0E6E]
open_hw_target

set_property PROGRAM.FILE {/net/top/homes/oshiro/odmb/firmware/odmb7_ucsb_dev/testbench/tb_project/tb_project.runs/impl_1/Firmware_tb.bit} [get_hw_devices xcku040_0]
set_property PROBES.FILE {/net/top/homes/oshiro/odmb/firmware/odmb7_ucsb_dev/testbench/tb_project/tb_project.runs/impl_1/Firmware_tb.ltx} [get_hw_devices xcku040_0]
set_property FULL_PROBES.FILE {/net/top/homes/oshiro/odmb/firmware/odmb7_ucsb_dev/testbench/tb_project/tb_project.runs/impl_1/Firmware_tb.ltx} [get_hw_devices xcku040_0]
current_hw_device [get_hw_devices xcku040_0]
program_hw_devices [get_hw_devices xcku040_0]
refresh_hw_device [lindex [get_hw_devices xcku040_0] 0]

set_property OUTPUT_VALUE 1 [get_hw_probes use_vio_input_vector -of_objects [get_hw_vios -of_objects [get_hw_devices xcku040_0] -filter {CELL_NAME=~"vio_input_i"}]]
commit_hw_vio [get_hw_probes {use_vio_input_vector} -of_objects [get_hw_vios -of_objects [get_hw_devices xcku040_0] -filter {CELL_NAME=~"vio_input_i"}]]

set user_input ""
puts "Ready for user VME commands"
while { $user_input != "exit" } {
  gets stdin user_input
  if { [string index $user_input 0]=="R" || [string index $user_input 0]=="r"} {
    if { [string length $user_input]<6 } {
      puts "Read command insufficient length"
    } else {
      #read commands
      #puts "Read"
      #puts [string range $user_input 2 5]
      set_property OUTPUT_VALUE [string range $user_input 2 5] [get_hw_probes vio_vme_addr -of_objects [get_hw_vios -of_objects [get_hw_devices xcku040_0] -filter {CELL_NAME=~"vio_input_i"}]]
      commit_hw_vio [get_hw_probes {vio_vme_addr} -of_objects [get_hw_vios -of_objects [get_hw_devices xcku040_0] -filter {CELL_NAME=~"vio_input_i"}]]
      set_property OUTPUT_VALUE "2EAD" [get_hw_probes vio_vme_data -of_objects [get_hw_vios -of_objects [get_hw_devices xcku040_0] -filter {CELL_NAME=~"vio_input_i"}]]
      commit_hw_vio [get_hw_probes {vio_vme_data} -of_objects [get_hw_vios -of_objects [get_hw_devices xcku040_0] -filter {CELL_NAME=~"vio_input_i"}]]
      set_property OUTPUT_VALUE 1 [get_hw_probes vio_issue_vme_cmd_vector -of_objects [get_hw_vios -of_objects [get_hw_devices xcku040_0] -filter {CELL_NAME=~"vio_input_i"}]]
      commit_hw_vio [get_hw_probes {vio_issue_vme_cmd_vector} -of_objects [get_hw_vios -of_objects [get_hw_devices xcku040_0] -filter {CELL_NAME=~"vio_input_i"}]]
      after 100
      set_property OUTPUT_VALUE 0 [get_hw_probes vio_issue_vme_cmd_vector -of_objects [get_hw_vios -of_objects [get_hw_devices xcku040_0] -filter {CELL_NAME=~"vio_input_i"}]]
      commit_hw_vio [get_hw_probes {vio_issue_vme_cmd_vector} -of_objects [get_hw_vios -of_objects [get_hw_devices xcku040_0] -filter {CELL_NAME=~"vio_input_i"}]]
      after 500
      puts [get_property INPUT_VALUE [get_hw_probes vio_vme_out]]
    }
  } elseif { [string index $user_input 0]=="W" || [string index $user_input 0]=="w"} {
    if { [string length $user_input]<11 } {
      puts "Write command insufficient length"
    } else {
      #write commands
      #puts "Write"
      #puts [string range $user_input 2 5]
      #puts [string range $user_input 7 10]
      set_property OUTPUT_VALUE [string range $user_input 2 5] [get_hw_probes vio_vme_addr -of_objects [get_hw_vios -of_objects [get_hw_devices xcku040_0] -filter {CELL_NAME=~"vio_input_i"}]]
      commit_hw_vio [get_hw_probes {vio_vme_addr} -of_objects [get_hw_vios -of_objects [get_hw_devices xcku040_0] -filter {CELL_NAME=~"vio_input_i"}]]
      set_property OUTPUT_VALUE [string range $user_input 7 10] [get_hw_probes vio_vme_data -of_objects [get_hw_vios -of_objects [get_hw_devices xcku040_0] -filter {CELL_NAME=~"vio_input_i"}]]
      commit_hw_vio [get_hw_probes {vio_vme_data} -of_objects [get_hw_vios -of_objects [get_hw_devices xcku040_0] -filter {CELL_NAME=~"vio_input_i"}]]
      set_property OUTPUT_VALUE 1 [get_hw_probes vio_issue_vme_cmd_vector -of_objects [get_hw_vios -of_objects [get_hw_devices xcku040_0] -filter {CELL_NAME=~"vio_input_i"}]]
      commit_hw_vio [get_hw_probes {vio_issue_vme_cmd_vector} -of_objects [get_hw_vios -of_objects [get_hw_devices xcku040_0] -filter {CELL_NAME=~"vio_input_i"}]]
      after 100
      set_property OUTPUT_VALUE 0 [get_hw_probes vio_issue_vme_cmd_vector -of_objects [get_hw_vios -of_objects [get_hw_devices xcku040_0] -filter {CELL_NAME=~"vio_input_i"}]]
      commit_hw_vio [get_hw_probes {vio_issue_vme_cmd_vector} -of_objects [get_hw_vios -of_objects [get_hw_devices xcku040_0] -filter {CELL_NAME=~"vio_input_i"}]]
    }
  }
}

close_hw
