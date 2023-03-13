# This sets continuous sequence mode, and calibration mode
set_hw_sysmon_reg [lindex [get_hw_sysmons] 0 ] 41 2080
# This turns on the voltage monitors
set_hw_sysmon_reg [lindex [get_hw_sysmons] 0 ] 48 7F01
# This turns on the ADC channels (turn all on)
set_hw_sysmon_reg [lindex [get_hw_sysmons] 0 ] 49 FFFF
