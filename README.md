# ODMB7 Development

This repository can be used for porting parts of the ODMB7 firmware from the ODMB and for testing it in simulation and on the KCU105 evaluation board. 

## Structure

### ODMB firmware
The top module of ODMB firmware is contained in the interface [odmb7_ucsb_dev.vhd](/source/odmb7_ucsb_dev.vhd), which then manages signals and sends them to
appropriate submodules as they are ported. 

#### Porting guidelines
- The naming of the signals in the top module should follow the signal names connected to the FPGA in the schematic as much as possible, except when they shall be
  improved to give more clarity  (e.g. `C_TDO` --> `DCFEB_TDO`, `DONE` --> `DCFEB_DONE`), in such case, the real signal name shall be attached as comment.

- The position of the pin (which Bank it is connected to) shall be attached as comment in the entity declaration.

- Try to assign every connected signal a corresponding signal in the entity declaration, even if they are unused for now (just to keep the record).


### Testbench
The top-level testbench file is [Firmware_tb.vhd](testbench/source/Firmware_tb.vhd). This will contain the ODMB firmware, the simulated VME, DCFEBs, and possibly
other devices in the future. LUTs are used to provide VME commands to the ODMB, and its eventual response is given to an ILA. 


## Progress

- [ ] Port ODMB_VME 
  - [X] COMMAND_MODULE
  - [ ] Device 0: TESTCTRL
  - [X] Device 1: CFEBJTAG
    - [X] Import VME simulation
    - [X] Import DCFEB simulation (only user code reading)
  - [X] Device 2: ODMBJTAG
  - [X] Device 3: VMEMON
  - [X] Device 4: VMECONFREGS
  - [ ] Device 5: TESTFIFOS
  - [X] Device 6: SPI_PORT
    - [X] CFG Register upload/download
    - [X] Write Command FIFO
    - [X] Read readback FIFO
    - [X] SPI state machine commands
    - [X] Read SPI status/timer
  - [X] Device 7: SYSTEM_MON
  - [X] Device 8: LVDBMON
    - [X] Import LVDB module
  - [ ] Device 9: SYSTEM_TEST
    - [X] Import OTMB PRBS test
    - [ ] Import the Optical PRBS tests
  - [ ] SPI_CTRL
    - [X] Read/write/erase PROM commands
    - [X] Other PROM commands (status/lock/unlock/check)
    - [X] Timer commands

