set_property PACKAGE_PIN AK17 [get_ports CLK_IN_P]
set_property IOSTANDARD  DIFF_SSTL12 [get_ports CLK_IN_P]
set_property ODT         RTT_48 [get_ports CLK_IN_P]

set_property PACKAGE_PIN AK16 [get_ports CLK_IN_N]
set_property IOSTANDARD  DIFF_SSTL12 [get_ports CLK_IN_N]
set_property ODT         RTT_48 [get_ports CLK_IN_N]

set_property PACKAGE_PIN H27 [get_ports J36_USER_SMA_GPIO_P]
set_property IOSTANDARD  LVCMOS18 [get_ports J36_USER_SMA_GPIO_P]

# Constrain only P side of the clock: https://www.xilinx.com/support/answers/57109.html
#Handled by clock manager now
#create_clock -period 3.333 -name clk_in [get_ports CLK_IN_P]
#set_input_jitter [get_clocks -of_objects [get_ports CLK_IN_P]] 0.033

# get_ports vs get_pins: https://electronics.stackexchange.com/questions/339401/get-ports-vs-get-pins-vs-get-nets-vs-get-registers
# To match timing from same source clock: https://forums.xilinx.com/t5/Timing-Analysis/CLOCK-DELAY-GROUP-doesn-t-seem-to-be-working/td-p/899055

##########################   Bitstream options #####################################
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property BITSTREAM.CONFIG.CONFIGFALLBACK ENABLE [current_design]
set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR YES [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design] 
set_property CONFIG_VOLTAGE 1.8 [current_design] 
set_property CFGBVS GND [current_design] 
