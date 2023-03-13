#!/usr/bin/tclsh

#This script emulates the DAQMB::odmb_program_eprom function found in EmuLib
#for the case of simulated ODMB7 firmware running on the KCU105 evaluation
#board
#
#run with vivado -nojournal -nolog -mode batch -notrace -source vme_program_eprom.tcl

#settings
set DEBUG_MODE 0

set num_spi_cmds 0

#
#function that executes a VME commands by communication with the VIO on the KCU105
#
proc execute_vme_command {ADDR DATA} {
  #upvar $DEBUG_MODE DEBUG_MODE
  global DEBUG_MODE
  if {$DATA == "2EAD"} {
    if {$DEBUG_MODE == 1} {
      puts "Executing read command."
    }
  }
  if {$DEBUG_MODE == 1} {
    puts "VME $ADDR $DATA"
  } else {
    puts "VME $ADDR $DATA"
    set_property OUTPUT_VALUE $ADDR [get_hw_probes vio_vme_addr -of_objects [get_hw_vios -of_objects [get_hw_devices xcku040_0] -filter {CELL_NAME=~"vio_input_i"}]]
    commit_hw_vio [get_hw_probes {vio_vme_addr} -of_objects [get_hw_vios -of_objects [get_hw_devices xcku040_0] -filter {CELL_NAME=~"vio_input_i"}]]
    after 100
    set_property OUTPUT_VALUE $DATA [get_hw_probes vio_vme_data -of_objects [get_hw_vios -of_objects [get_hw_devices xcku040_0] -filter {CELL_NAME=~"vio_input_i"}]]
    commit_hw_vio [get_hw_probes {vio_vme_data} -of_objects [get_hw_vios -of_objects [get_hw_devices xcku040_0] -filter {CELL_NAME=~"vio_input_i"}]]
    after 100
    set_property OUTPUT_VALUE 1 [get_hw_probes vio_issue_vme_cmd_vector -of_objects [get_hw_vios -of_objects [get_hw_devices xcku040_0] -filter {CELL_NAME=~"vio_input_i"}]]
    commit_hw_vio [get_hw_probes {vio_issue_vme_cmd_vector} -of_objects [get_hw_vios -of_objects [get_hw_devices xcku040_0] -filter {CELL_NAME=~"vio_input_i"}]]
    after 100
    set_property OUTPUT_VALUE 0 [get_hw_probes vio_issue_vme_cmd_vector -of_objects [get_hw_vios -of_objects [get_hw_devices xcku040_0] -filter {CELL_NAME=~"vio_input_i"}]]
    commit_hw_vio [get_hw_probes {vio_issue_vme_cmd_vector} -of_objects [get_hw_vios -of_objects [get_hw_devices xcku040_0] -filter {CELL_NAME=~"vio_input_i"}]]
    after 400
  }
}

#
#function that adds to the number of spi commands executed and checks value against firmware
#
proc add_to_spi_cmd_num {ADDAND} {
  global num_spi_cmds
  set num_spi_cmds [expr $num_spi_cmds + $ADDAND]
  execute_vme_command "6108" "2EAD"
  set fpga_num_spi_cmds [get_property INPUT_VALUE [get_hw_probes vio_vme_out]]
  scan $fpga_num_spi_cmds %x fpga_num_spi_cmds_dec
  if {$fpga_num_spi_cmds_dec != $num_spi_cmds} {
    puts "ERROR: $num_spi_cmds SPI commands sent, but $fpga_num_spi_cmds_dec received"
    #execute_vme_command "6104" "2EAD"
    #set fpga_num_cmds [get_property INPUT_VALUE [get_hw_probes vio_vme_out]]
    #scan $fpga_num_cmds %x fpga_num_cmds_dec
    #puts "Note: $fpga_num_cmds_dev total 602C commands received"
    close_hw
    exit
  }
}

#
#function that sends VME commands for loading PROM address
#
proc odmbeprom_loadaddress {uaddr laddr} {
  set upper_load_addr [expr [expr [expr $uaddr << 5] & 0xFFE0 ] | 0x17]
  set upper_load_addr [format %04X $upper_load_addr]
  set laddr [format %04X $laddr]
  execute_vme_command "602C" $upper_load_addr
  execute_vme_command "602C" $laddr
  add_to_spi_cmd_num 1
}

#
#function that sends VME commands for programming the PROM
#
proc odmbeprom_bufferprogram {nwords bindata position} {
  set tmp [expr [expr [expr [expr $nwords - 1] << 5] & 0xFFE0] | 0x0C]
  set tmp [format %04X $tmp]
  execute_vme_command "602C" $tmp
  after 1
  for {set i 0} {$i < $nwords} {incr i} {
    binary scan [string index $bindata [expr [expr $position * 2] + [expr $i * 2]]] H2 first_char
    after 1
    binary scan [string index $bindata [expr [expr [expr $position * 2] + [expr $i * 2]] + 1]] H2 second_char
    after 1
    set hex_string $first_char
    append hex_string $second_char
    execute_vme_command "602C" $hex_string
  }
  add_to_spi_cmd_num 1
}

#
#main function, sends VME commands to program eprom
#
proc main {} {
  global DEBUG_MODE
  #setup KCU105 connection
  if {$DEBUG_MODE == 0} {
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
  }
  #startup stuff
  #firmware/block/write size in words
  #set FIRMWARE_SIZE [expr 5464972 / 2]
  set FIRMWARE_SIZE [expr 0x8000]
  set BLOCK_SIZE 0x8000 ;#half the size of the old sectors
  set WRITE_SIZE 0x40 ;#1/2 page, previously 0x400. Could go higher
  set input_file [open "../cfg_reg_prom_test.bin" r]
  fconfigure $input_file -translation binary
  set bindata [read $input_file] ;#hopefully no memory issues??
  close $input_file
  execute_vme_command "6020" "0000" ;#BPI reset
  execute_vme_command "6028" "0000" ;#BPI enable
  execute_vme_command "602C" "001A" ;#BPI timer stop
  execute_vme_command "602C" "001B" ;#BPI timer reset
  execute_vme_command "602C" "0019" ;#BPI timer start
  add_to_spi_cmd_num 3
  #erase EPROM memory
  set blocks [expr $FIRMWARE_SIZE / $BLOCK_SIZE]
  if { [expr $FIRMWARE_SIZE % $BLOCK_SIZE] > 0 } {
    incr blocks
  }
  puts "Erasing EPROM..."
  set fulladdr 0
  for {set i 0} {$i<$blocks} {incr i} {
    set uaddr [expr $fulladdr >> 16]
    set laddr [expr $fulladdr & 0xFFFF]
    odmbeprom_loadaddress $uaddr $laddr
    execute_vme_command "602C" "0014" ;#BPI unlock
    execute_vme_command "602C" "000A" ;#BPI block erase
    add_to_spi_cmd_num 2
    set fulladdr [expr $fulladdr + [expr 2 * $BLOCK_SIZE]]
    after 1000
    #if {$i == 1} {
    #  break
    #}
  }
  #write to EPROM
  puts "Programming EPROM..."
  set blocks [expr $FIRMWARE_SIZE / $WRITE_SIZE]
  set lastblock [expr $FIRMWARE_SIZE % $WRITE_SIZE]
  set fulladdr 0
  for {set i 0} {$i < $blocks} {incr i} {
    puts "Writing block $i"
    set nwords $WRITE_SIZE
    if {$i == [expr $blocks - 1]} {
      set nwords $lastblock
    }
    set uaddr [expr $fulladdr >> 16]
    set laddr [expr $fulladdr & 0xFFFF]
    odmbeprom_loadaddress $uaddr $laddr
    odmbeprom_bufferprogram $nwords $bindata [expr $i * $WRITE_SIZE]
    after 100
    set fulladdr [expr $fulladdr + [expr 2 * $WRITE_SIZE]]
    #progress bar here
    if {$i == 4} {
      break
    }
  }
  puts "Sending 100%..."
  set uaddr [expr $fulladdr >> 16]
  set laddr [expr $fulladdr & 0xFFFF]
  odmbeprom_loadaddress $uaddr $laddr
  execute_vme_command "602C" "0013" ;#BPI lock
  add_to_spi_cmd_num 1
  after 100
  execute_vme_command "6024" "0000" ;#BPI disable
  if {$DEBUG_MODE == 0} {
    close_hw
  }
}

main
