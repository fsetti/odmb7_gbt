# Testbench for the datafifo IP core 
This testbench uses the template from the [KintexUltraScale Testbench Template](https://github.com/odmb/odmbDevelopment)
Only the source folder is requried. Other folders can be generated using the generator tcl files.

## Generator files
- source/ip_generator.tcl: Tcl file that can generate IPs according to the FPGA
- source/tb_project_generator.tcl: Tcl file that can generate testbench Vivado project

## To make the testbench project, run the below commands. The testbench is targeted for the KCU105 board.
~~~~bash
cd source; vivado -nojournal -nolog -mode batch -source tb_project_generator.tcl
~~~~

## To re-make the ip cores, run one of the below command according to the FPGA target
~~~~bash
cd source; vivado -nojournal -nolog -mode batch -source ip_generator.tcl -tclargs xcku040-ffva1156-2-e
~~~~
