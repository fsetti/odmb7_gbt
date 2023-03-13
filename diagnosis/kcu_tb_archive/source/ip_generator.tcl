if { $argc != 1 } {
  puts "\[Error\] Please type in one of the below commands in the source directory"
  puts "vivado -nojournal -nolog -mode batch -source ip_generator.tcl -tclargs xcku040-ffva1156-2-e"
  puts "vivado -nojournal -nolog -mode batch -source ip_generator.tcl -tclargs xcku035-ffva1156-1-c"
} else {
  # Set environment variable
  set FPGA_TYPE [lindex $argv 0] 

  # Create ip project manager
  create_project managed_ip_project ../ip/$FPGA_TYPE/managed_ip_project -part $FPGA_TYPE -ip -force
  set_property target_language VHDL [current_project]
  set_property target_simulator XSim [current_project]
  
  # Create clockManager
  create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name clockManager -dir ../ip/$FPGA_TYPE
  set_property -dict [list CONFIG.PRIM_IN_FREQ {300} CONFIG.CLKOUT2_USED {true} CONFIG.CLKOUT3_USED {true} CONFIG.CLKOUT4_USED {true} CONFIG.PRIMARY_PORT {clk_in300} CONFIG.CLK_OUT1_PORT {clk_out40} CONFIG.CLK_OUT2_PORT {clk_out10} CONFIG.CLK_OUT3_PORT {clk_out80} CONFIG.CLK_OUT4_PORT {clk_out160} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {40} CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {10} CONFIG.CLKOUT3_REQUESTED_OUT_FREQ {80.000} CONFIG.CLKOUT4_REQUESTED_OUT_FREQ {160.000} CONFIG.USE_LOCKED {false} CONFIG.USE_RESET {false} CONFIG.CLKIN1_JITTER_PS {33.330000000000005} CONFIG.MMCM_DIVCLK_DIVIDE {5} CONFIG.MMCM_CLKIN1_PERIOD {3.333} CONFIG.MMCM_CLKIN2_PERIOD {10.0} CONFIG.MMCM_CLKFBOUT_MULT_F {16.000} CONFIG.MMCM_CLKOUT0_DIVIDE_F {24.000} CONFIG.MMCM_CLKOUT1_DIVIDE {96} CONFIG.MMCM_CLKOUT2_DIVIDE {12} CONFIG.MMCM_CLKOUT3_DIVIDE {6} CONFIG.NUM_OUT_CLKS {4} CONFIG.CLKOUT1_JITTER {155.514} CONFIG.CLKOUT2_JITTER {203.128} CONFIG.CLKOUT2_PHASE_ERROR {98.575} CONFIG.CLKOUT3_JITTER {129.666} CONFIG.CLKOUT3_PHASE_ERROR {98.575} CONFIG.CLKOUT4_JITTER {135.961} CONFIG.CLKOUT4_PHASE_ERROR {121.733} CONFIG.CLKOUT1_DRIVES {BUFG} CONFIG.CLKOUT2_DRIVES {BUFG} CONFIG.CLKOUT3_DRIVES {BUFG} CONFIG.CLKOUT4_DRIVES {BUFG} CONFIG.FEEDBACK_SOURCE {FDBK_AUTO} CONFIG.CLKOUT1_MATCHED_ROUTING {true} CONFIG.CLKOUT2_MATCHED_ROUTING {true} CONFIG.CLKOUT3_MATCHED_ROUTING {true} CONFIG.CLKOUT4_MATCHED_ROUTING {true} CONFIG.PRIM_SOURCE {No_buffer}] [get_ips clockManager]
 
  # Create ila
  create_ip -name ila -vendor xilinx.com -library ip -module_name ila -dir ../ip/$FPGA_TYPE
  set_property -dict [list CONFIG.C_PROBE1_TYPE {1} CONFIG.C_PROBE0_TYPE {2} CONFIG.C_PROBE1_WIDTH {4096} CONFIG.C_PROBE0_WIDTH {256} CONFIG.C_NUM_OF_PROBES {2} CONFIG.ALL_PROBE_SAME_MU {false}] [get_ips ila]
  
  # Create lut_input1
  create_ip -name blk_mem_gen -vendor xilinx.com -library ip -module_name lut_input1 -dir ../ip/$FPGA_TYPE
  set_property -dict [list CONFIG.Memory_Type {Single_Port_ROM} CONFIG.Write_Width_A {16} CONFIG.Write_Depth_A {16} CONFIG.Enable_A {Always_Enabled} CONFIG.Register_PortA_Output_of_Memory_Primitives {false} CONFIG.Load_Init_File {true} CONFIG.Coe_File {../../../source/data/Input1.coe} CONFIG.Read_Width_A {16} CONFIG.Write_Width_B {16} CONFIG.Read_Width_B {16} CONFIG.Port_A_Write_Rate {0}] [get_ips lut_input1]
  #set_property -dict [list CONFIG.Memory_Type {Single_Port_ROM} CONFIG.Write_Width_A {12} CONFIG.Write_Depth_A {128} CONFIG.Enable_A {Always_Enabled} CONFIG.Register_PortA_Output_of_Memory_Primitives {false} CONFIG.Load_Init_File {true} CONFIG.Coe_File {../../../source/data/Input1.coe} CONFIG.Read_Width_A {12} CONFIG.Write_Width_B {12} CONFIG.Read_Width_B {12} CONFIG.Port_A_Write_Rate {0}] [get_ips lut_input1]
  #set_property -dict [list CONFIG.Write_Width_A {16} CONFIG.Write_Depth_A {8} CONFIG.Read_Width_A {16} CONFIG.Write_Width_B {16} CONFIG.Read_Width_B {16}] [get_ips lut_input1]
  
  # Create lut_input2
  create_ip -name blk_mem_gen -vendor xilinx.com -library ip -module_name lut_input2 -dir ../ip/$FPGA_TYPE
  set_property -dict [list CONFIG.Memory_Type {Single_Port_ROM} CONFIG.Write_Width_A {16} CONFIG.Write_Depth_A {16} CONFIG.Enable_A {Always_Enabled} CONFIG.Register_PortA_Output_of_Memory_Primitives {false} CONFIG.Load_Init_File {true} CONFIG.Coe_File {../../../source/data/Input2.coe} CONFIG.Read_Width_A {16} CONFIG.Write_Width_B {16} CONFIG.Read_Width_B {16} CONFIG.Port_A_Write_Rate {0}] [get_ips lut_input2]
  #set_property -dict [list CONFIG.Write_Width_A {16} CONFIG.Write_Depth_A {8} CONFIG.Read_Width_A {16} CONFIG.Write_Width_B {16} CONFIG.Read_Width_B {16}] [get_ips lut_input2]
  #set_property -dict [list CONFIG.Memory_Type {Single_Port_ROM} CONFIG.Write_Width_A {12} CONFIG.Write_Depth_A {128} CONFIG.Enable_A {Always_Enabled} CONFIG.Register_PortA_Output_of_Memory_Primitives {false} CONFIG.Load_Init_File {true} CONFIG.Coe_File {../../../source/data/Input2.coe} CONFIG.Read_Width_A {12} CONFIG.Write_Width_B {12} CONFIG.Read_Width_B {12} CONFIG.Port_A_Write_Rate {0}] [get_ips lut_input2]
  #set_property -dict [list CONFIG.Write_Width_A {16} CONFIG.Write_Depth_A {8} CONFIG.Read_Width_A {16} CONFIG.Write_Width_B {16} CONFIG.Read_Width_B {16}] [get_ips lut_input2]

  # Create VIO
  create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_input -dir ../ip/$FPGA_TYPE
  set_property -dict [list CONFIG.C_PROBE_IN0_WIDTH {16} CONFIG.C_PROBE_OUT3_WIDTH {16} CONFIG.C_PROBE_OUT2_WIDTH {16} CONFIG.C_NUM_PROBE_OUT {4} CONFIG.C_NUM_PROBE_IN {1} CONFIG.C_EN_PROBE_IN_ACTIVITY {0} CONFIG.C_PROBE_OUT0_INIT_VAL {0x1}] [get_ips vio_input]

  #ODMB IP cores
  #create spi_cmd_fifo
  create_ip -name fifo_generator -vendor xilinx.com -library ip -module_name spi_cmd_fifo -dir ../ip/$FPGA_TYPE
set_property -dict [list CONFIG.Fifo_Implementation {Independent_Clocks_Builtin_FIFO} CONFIG.Performance_Options {First_Word_Fall_Through} CONFIG.Input_Data_Width {16} CONFIG.Read_Clock_Frequency {40} CONFIG.Write_Clock_Frequency {2} CONFIG.Output_Data_Width {16} CONFIG.Empty_Threshold_Assert_Value {6} CONFIG.Empty_Threshold_Negate_Value {7}] [get_ips spi_cmd_fifo]

  # Create spi_readback_fifo
  create_ip -name fifo_generator -vendor xilinx.com -library ip -module_name spi_readback_fifo -dir ../ip/$FPGA_TYPE
  set_property -dict [list CONFIG.Fifo_Implementation {Independent_Clocks_Builtin_FIFO} CONFIG.Input_Data_Width {16} CONFIG.Input_Depth {512} CONFIG.Read_Clock_Frequency {2} CONFIG.Write_Clock_Frequency {40} CONFIG.Output_Data_Width {16} CONFIG.Output_Depth {512} CONFIG.Data_Count_Width {9} CONFIG.Write_Data_Count_Width {9} CONFIG.Read_Data_Count_Width {9} CONFIG.Full_Threshold_Assert_Value {511} CONFIG.Full_Threshold_Negate_Value {510} CONFIG.Performance_Options {First_Word_Fall_Through} CONFIG.Empty_Threshold_Assert_Value {6} CONFIG.Empty_Threshold_Negate_Value {7}] [get_ips spi_readback_fifo]

  #create writeSpiFIFO
  create_ip -name fifo_generator -vendor xilinx.com -library ip -module_name writeSpiFIFO -dir ../ip/$FPGA_TYPE
  set_property -dict [list CONFIG.Fifo_Implementation {Independent_Clocks_Builtin_FIFO} CONFIG.Performance_Options {First_Word_Fall_Through} CONFIG.asymmetric_port_width {true} CONFIG.Input_Data_Width {16} CONFIG.Read_Clock_Frequency {40} CONFIG.Write_Clock_Frequency {40} CONFIG.Programmable_Full_Type {Single_Programmable_Full_Threshold_Constant} CONFIG.Full_Threshold_Assert_Value {64} CONFIG.Output_Data_Width {4} CONFIG.Output_Depth {8192} CONFIG.Read_Data_Count_Width {13} CONFIG.Full_Threshold_Negate_Value {63} CONFIG.Empty_Threshold_Assert_Value {4} CONFIG.Empty_Threshold_Negate_Value {5}] [get_ips writeSpiFIFO]

  #create OdmbClockManager
  #create_ip -name clk_wiz -vendor xilinx.com -library ip -version 5.4 -module_name OdmbClockManager
  create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name OdmbClockManager -dir ../ip/$FPGA_TYPE
  set_property -dict [list CONFIG.PRIMITIVE {MMCM} CONFIG.PRIM_SOURCE {Differential_clock_capable_pin} CONFIG.PRIM_IN_FREQ {40.000} CONFIG.JITTER_OPTIONS {UI} CONFIG.CLKOUT2_USED {true} CONFIG.CLKOUT3_USED {true} CONFIG.CLKOUT4_USED {true} CONFIG.CLKOUT5_USED {true} CONFIG.CLK_OUT1_PORT {clk_out160} CONFIG.CLK_OUT2_PORT {clk_out80} CONFIG.CLK_OUT3_PORT {clk_out40} CONFIG.CLK_OUT4_PORT {clk_out20} CONFIG.CLK_OUT5_PORT {clk_out10} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {160.000} CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {80.000} CONFIG.CLKOUT3_REQUESTED_OUT_FREQ {40.000} CONFIG.CLKOUT4_REQUESTED_OUT_FREQ {20.000} CONFIG.CLKOUT5_REQUESTED_OUT_FREQ {10.000} CONFIG.USE_LOCKED {false} CONFIG.USE_PHASE_ALIGNMENT {true} CONFIG.SECONDARY_SOURCE {Single_ended_clock_capable_pin} CONFIG.CLKIN1_UI_JITTER {0.010} CONFIG.CLKIN2_UI_JITTER {0.010} CONFIG.CLKIN1_JITTER_PS {250.0} CONFIG.CLKIN2_JITTER_PS {100.0} CONFIG.CLKOUT1_DRIVES {Buffer} CONFIG.CLKOUT2_DRIVES {Buffer} CONFIG.CLKOUT3_DRIVES {Buffer} CONFIG.CLKOUT4_DRIVES {Buffer} CONFIG.CLKOUT5_DRIVES {Buffer} CONFIG.CLKOUT6_DRIVES {Buffer} CONFIG.CLKOUT7_DRIVES {Buffer} CONFIG.FEEDBACK_SOURCE {FDBK_AUTO} CONFIG.MMCM_DIVCLK_DIVIDE {1} CONFIG.MMCM_CLKFBOUT_MULT_F {24.000} CONFIG.MMCM_CLKIN1_PERIOD {25.000} CONFIG.MMCM_CLKIN2_PERIOD {10.0} CONFIG.MMCM_COMPENSATION {AUTO} CONFIG.MMCM_REF_JITTER2 {0.010} CONFIG.MMCM_CLKOUT0_DIVIDE_F {6.000} CONFIG.MMCM_CLKOUT1_DIVIDE {12} CONFIG.MMCM_CLKOUT2_DIVIDE {24} CONFIG.MMCM_CLKOUT3_DIVIDE {48} CONFIG.MMCM_CLKOUT4_DIVIDE {96} CONFIG.NUM_OUT_CLKS {5} CONFIG.CLKOUT1_JITTER {169.111} CONFIG.CLKOUT1_PHASE_ERROR {196.976} CONFIG.CLKOUT2_JITTER {200.412} CONFIG.CLKOUT2_PHASE_ERROR {196.976} CONFIG.CLKOUT3_JITTER {247.096} CONFIG.CLKOUT3_PHASE_ERROR {196.976} CONFIG.CLKOUT4_JITTER {298.160} CONFIG.CLKOUT4_PHASE_ERROR {196.976} CONFIG.CLKOUT5_JITTER {342.201} CONFIG.CLKOUT5_PHASE_ERROR {196.976}] [get_ips OdmbClockManager]

  #create KcuClockManager
  create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name KcuClockManager -dir ../ip/$FPGA_TYPE
  set_property -dict [list CONFIG.PRIM_IN_FREQ {40.000} CONFIG.CLKOUT2_USED {true} CONFIG.CLKOUT3_USED {true} CONFIG.CLKOUT4_USED {true} CONFIG.CLKOUT5_USED {true} CONFIG.CLK_OUT1_PORT {clk_out160} CONFIG.CLK_OUT2_PORT {clk_out80} CONFIG.CLK_OUT3_PORT {clk_out40} CONFIG.CLK_OUT4_PORT {clk_out20} CONFIG.CLK_OUT5_PORT {clk_out10} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {160.000} CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {80.000} CONFIG.CLKOUT3_REQUESTED_OUT_FREQ {40.000} CONFIG.CLKOUT4_REQUESTED_OUT_FREQ {20.000} CONFIG.CLKOUT5_REQUESTED_OUT_FREQ {10.000} CONFIG.USE_LOCKED {false} CONFIG.CLKIN1_JITTER_PS {250.0} CONFIG.MMCM_DIVCLK_DIVIDE {1} CONFIG.MMCM_CLKFBOUT_MULT_F {24.000} CONFIG.MMCM_CLKIN1_PERIOD {25.000} CONFIG.MMCM_CLKIN2_PERIOD {10.0} CONFIG.MMCM_CLKOUT0_DIVIDE_F {6.000} CONFIG.MMCM_CLKOUT1_DIVIDE {12} CONFIG.MMCM_CLKOUT2_DIVIDE {24} CONFIG.MMCM_CLKOUT3_DIVIDE {48} CONFIG.MMCM_CLKOUT4_DIVIDE {96} CONFIG.NUM_OUT_CLKS {5} CONFIG.CLKOUT1_JITTER {169.111} CONFIG.CLKOUT1_PHASE_ERROR {196.976} CONFIG.CLKOUT2_JITTER {200.412} CONFIG.CLKOUT2_PHASE_ERROR {196.976} CONFIG.CLKOUT3_JITTER {247.096} CONFIG.CLKOUT3_PHASE_ERROR {196.976} CONFIG.CLKOUT4_JITTER {298.160} CONFIG.CLKOUT4_PHASE_ERROR {196.976} CONFIG.CLKOUT5_JITTER {342.201} CONFIG.CLKOUT5_PHASE_ERROR {196.976}] [get_ips KcuClockManager]

  puts "\[Success\] Created ip for $FPGA_TYPE"
  close_project
}
