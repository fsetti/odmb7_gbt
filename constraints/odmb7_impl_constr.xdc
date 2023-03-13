# Constraint on component xlx_ku_rx_dpram for CLOCKING_SCHEME = FULL_MGTFREQ and RX_OPTIMIZATION = STANDARD 
# Values depends on the RX_GEARBOXSYNCSHIFT_COUNT constant value defined into the gbt_bank_package.vhd file
set_multicycle_path 3 -from [get_pins -hier -filter {NAME =~  *gbt_inst*rxGearboxStd_gen*ram*}]  -end -setup
set_multicycle_path 2 -from [get_pins -hier -filter {NAME =~  *gbt_inst*rxGearboxStd_gen*ram*}]  -end -hold
