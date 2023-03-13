-------------------------------------------------------
--! @file
--! @brief top level file for ODMB7 prototype firmware
-------------------------------------------------------

library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_misc.all;

library unisim;
use unisim.vcomponents.all;

use work.ucsb_types.all;

--! @brief ODMB7 prototype firmware
--! @details ODMB7 firmware. Currently capable of testing virtually all 
--! hardware interfaces and performing most slow control functionality, however
--! data acquisition firmware has not yet been developed
entity odmb7_ucsb_dev is
  port (
    --------------------
    -- Input clocks
    --------------------
    CMS_CLK_FPGA_P : in std_logic;                         --! CMS/system clock: 40.07897 MHz. Can be from local oscillator or CCB. Used to generate most clocks used in firmware. Connected to bank 45.
    CMS_CLK_FPGA_N : in std_logic;                         --! CMS/system clock: 40.07897 MHz. Can be from local oscillator or CCB. Used to generate most clocks used in firmware. Connected to bank 45.
    GP_CLK_6_P     : in std_logic;                         --! From clock synthesizer ODIV6: 80 MHz. Currently unused. Connected to bank 44.
    GP_CLK_6_N     : in std_logic;                         --! From clock synthesizer ODIV6: 80 MHz. Currently unused. Connected to bank 44.
    GP_CLK_7_P     : in std_logic;                         --! From clock synthesizer ODIV7: 80 MHz. Currently unused. Connected to bank 68.
    GP_CLK_7_N     : in std_logic;                         --! From clock synthesizer ODIV7: 80 MHz. Currently unused. Connected to bank 68.
    REF_CLK_1_P    : in std_logic;                         --! From clock synthesizer, refclk0 to GTH quad 224.
    REF_CLK_1_N    : in std_logic;                         --! From clock synthesizer, refclk0 to GTH quad 224.
    REF_CLK_2_P    : in std_logic;                         --! From clock synthesizer, refclk0 to GTH quad 227.
    REF_CLK_2_N    : in std_logic;                         --! From clock synthesizer, refclk0 to GTH quad 227.
    REF_CLK_3_P    : in std_logic;                         --! From clock synthesizer, refclk0 to GTH quad 226.
    REF_CLK_3_N    : in std_logic;                         --! From clock synthesizer, refclk0 to GTH quad 226.
    REF_CLK_4_P    : in std_logic;                         --! From clock synthesizer, refclk0 to GTH quad 225.
    REF_CLK_4_N    : in std_logic;                         --! From clock synthesizer, refclk0 to GTH quad 225.
    REF_CLK_5_P    : in std_logic;                         --! From clock synthesizer, refclk1 to GTH quad 227.
    REF_CLK_5_N    : in std_logic;                         --! From clock synthesizer, refclk1 to GTH quad 227.
    CLK_125_REF_P  : in std_logic;                         --! From clock synthesizer, refclk1 to GTH quad 226.
    CLK_125_REF_N  : in std_logic;                         --! From clock synthesizer, refclk1 to GTH quad 226.
    LF_CLK         : in std_logic;                         --! From clock synthesizer, 10 kHz. General purpose low frequency clock, currently unused. Connected to bank 45.

    --------------------
    -- Signals controlled by ODMB_VME
    --------------------
    -- From/To VME controller to/from MBV
    VME_DATA        : inout std_logic_vector(15 downto 0); --! Data to/from VME backplane. Used by ODMB_VME module. Connected to bank 48.
    VME_GAP_B       : in std_logic;                        --! Geographical address (VME slot) parity. Used by ODMB_VME module. Connected to bank 48.
    VME_GA_B        : in std_logic_vector(4 downto 0);     --! Geographical address (VME slot). Used by ODMB_VME and ODMB CTRL module. Connected to bank 48.
    VME_ADDR        : in std_logic_vector(23 downto 1);    --! VME address (command). Used by ODMB_VME module. Conencted to bank 46.
    VME_AM          : in std_logic_vector(5 downto 0);     --! VME address modifier. Used by ODMB_VME module. Connected to cank 46.
    VME_AS_B        : in std_logic;                        --! VME address strobe. Used by ODMB_VME module. Connected to bank 46.
    VME_DS_B        : in std_logic_vector(1 downto 0);     --! VME data strobe. Used by ODMB_VME module. Connected to bank 46.
    VME_LWORD_B     : in std_logic;                        --! VME data word length. Used by ODMB_VME module. Connected to bank 48.
    VME_WRITE_B     : in std_logic;                        --! VME write/read indicator. Used by ODMB_VME module. Connected to bank 48.
    VME_IACK_B      : in std_logic;                        --! VME interrupt acknowledge. Used by ODMB_VME module. Connected to bank 48.
    VME_BERR_B      : in std_logic;                        --! VME bus error indicator. Used by ODMB_VME module. Connected to bank 48.
    VME_SYSRST_B    : in std_logic;                        --! VME system reset. Not used. Connected to bank 48.
    VME_SYSFAIL_B   : in std_logic;                        --! VME system failure indicator. Used by ODMB_VME module. Connected to bank 48.
    VME_CLK_B       : in std_logic;                        --! VME clock. Not used. Connected to bank 48.
    KUS_VME_OE_B    : out std_logic;                       --! VME output enable. Controlled by ODMB_VME module. Connected to bank 44.
    KUS_VME_DIR     : out std_logic;                       --! ODMB board VME input/output direction. Controlled by ODMB_VME module. Connected to bank 44.
    VME_DTACK_KUS_B : out std_logic;                       --! VME data acknowledge. Controlled by ODMB_VME module. Connected to bank 44.

    -- From/To PPIB (connectors J3 and J4)
    DCFEB_TCK_P    : out std_logic_vector(7 downto 1);     --! (x)DCFEB JTAG TCK signal. One per (x)DCFEB. Used by ODMB_VME module. Connected to bank 68.
    DCFEB_TCK_N    : out std_logic_vector(7 downto 1);     --! (x)DCFEB JTAG TCK signal. One per (x)DCFEB. Used by ODMB_VME module. Connected to bank 68. 
    DCFEB_TMS_P    : out std_logic;                        --! (x)DCFEB JTAG TMS signal. Used by ODMB_VME module. Connected to bank 68.
    DCFEB_TMS_N    : out std_logic;                        --! (x)DCFEB JTAG TMS signal. Used by ODMB_VME module. Connected to bank 68.
    DCFEB_TDI_P    : out std_logic;                        --! (x)DCFEB JTAG TDI signal. Used by ODMB_VME module. Connected to bank 68.
    DCFEB_TDI_N    : out std_logic;                        --! (x)DCFEB JTAG TDI signal. Used by ODMB_VME module. Connected to bank 68.
    DCFEB_TDO_P    : in  std_logic_vector(7 downto 1);     --! (x)DCFEB JTAG TDO signal. One per (x)DCFEB. Used by ODMB_VME module. Connected to bank 67-68 as "C_TDO".
    DCFEB_TDO_N    : in  std_logic_vector(7 downto 1);     --! (x)DCFEB JTAG TDO signal. One per (x)DCFEB. Used by ODMB_VME module. Connected to bank 67-68 as "C_TDO". 
    DCFEB_DONE     : in  std_logic_vector(7 downto 1);     --! (x)DCFEB programming done signal. Used only by top level DCFEB startup process. Connected to bank 68 as "DONE_*".
    RESYNC_P       : out std_logic;                        --! (x)DCFEB resync signal. Used by ODMB_VME module. Connected to bank 66.
    RESYNC_N       : out std_logic;                        --! (x)DCFEB resync signal. Used by ODMB_VME module. Connected to bank 66.
    BC0_P          : out std_logic;                        --! (x)DCFEB bunch crossing 0 synchronization signal. Initiated by CCB_BX0 signal or from ODMB_VME. Connected to bank 68.
    BC0_N          : out std_logic;                        --! (x)DCFEB bunch crossing 0 synchronization signal. Initiated by CCB_BX0 signal or from ODMB_VME. Connected to bank 68.
    INJPLS_P       : out std_logic;                        --! Calibration INJPLS signal for (x)DCFEBs. From ODMB CTRL module. Connected to bank 66.
    INJPLS_N       : out std_logic;                        --! Calibration INJPLS signal for (x)DCFEBs. From ODMB CTRL module. Connected to bank 66.
    EXTPLS_P       : out std_logic;                        --! Calibration EXTPLS signal for (x)DCFEBs. From ODMB CTRL module. Connected to bank 66.
    EXTPLS_N       : out std_logic;                        --! Calibration EXTPLS signal for (x)DCFEBs. From ODMB CTRL module. Connected to bank 66.
    L1A_P          : out std_logic;                        --! Trigger L1A signal for (x)DCFEBs. From ODMB CTRL module. Connected to bank 66.
    L1A_N          : out std_logic;                        --! Trigger L1A signal for (x)DCFEBs. From ODMB CTRL module. Connected to bank 66.
    L1A_MATCH_P    : out std_logic_vector(7 downto 1);     --! L1A match for (x)DCFEBs. From ODMB CTRL module. Connected to bank 66.
    L1A_MATCH_N    : out std_logic_vector(7 downto 1);     --! L1A match for (x)DCFEBs. From ODMB CTRL module. Connected to bank 66.
    PPIB_OUT_EN_B  : out std_logic;                        --! PPIB output enable signal. Should be fixed to '0'. Connected to bank 68.
    DCFEB_REPROG_B : out std_logic;                        --! (x)DCFEB reprogram signal. From ODMBCTRL in ODMB_VME module. Connected to bank 68.

    --------------------
    -- CCB Signals
    --------------------
    CCB_CMD        : in  std_logic_vector(5 downto 0);     --! Command from CCB, generates BC0, L1ARST, etc. for ODMB. Used by ODMB CTRL module. Connected to bank 44.
    CCB_CMD_S      : in  std_logic;                        --! CCB command strobe. Used by ODMB CTRL module. Connected to bank 46.
    CCB_DATA       : in  std_logic_vector(7 downto 0);     --! CCB data. Only used in CCB communication test. Connected to bank 44.
    CCB_DATA_S     : in  std_logic;                        --! CCB data strobe. Only used in CCB communication test. Connected to bank 46.
    CCB_CAL        : in  std_logic_vector(2 downto 0);     --! CCB calibration signals. Only used in CCB communication test. In ODMB2014 fw, connected to ODMB CTRL but unused. Connected to bank 44.
    CCB_CRSV       : in  std_logic_vector(3 downto 0);     --! CCB CCB-reserved signals. Only used in CCB communication test. In ODMB2014 fw, connected to ODMB CTRL but unused. Connected to bank 44.
    CCB_DRSV       : in  std_logic_vector(1 downto 0);     --! CCB DMB-reserved signals. Only used in CCB communication test. In ODMB2014 fw, connected to ODMB CTRL but unused. Connected to bank 45.
    CCB_RSVO       : in  std_logic_vector(4 downto 0);     --! CCB DMB-reserved output. Only used in CCB communication test. In ODMB2014 fw, connected to ODMB CTRL but unused. Connected to bank 45.
    CCB_RSVI       : out std_logic_vector(2 downto 0);     --! CCB DMB-reserved input. Only used in CCB communication test. In ODMB2014 fw, connected to ODMB CTRL but unused. Connected to bank 45.
    CCB_BX0_B      : in  std_logic;                        --! CCB bunch-crossing 0 synchronization signal. Used to generate BC0 pulse to (x)DCFEBs. Connected to Bank 46 as "CCB_BX0".
    CCB_BX_RST_B   : in  std_logic;                        --! CCB bunch-crossing reset signal. Used by ODMB CTRL. Connected to bank 46 as "CCB_BX_RST".
    CCB_L1A_RST_B  : in  std_logic;                        --! CCB L1A reset signal. Used by simulated FE boards but not ODMB CTRL in ODMB2014 fw. Connected to bank 46 as "CCB_L1A_RST".
    CCB_L1A_B      : in  std_logic;                        --! CCB L1A signal. Used to generate raw_l1a to ODMB CTRL in ODMB2014 fw. Connected to bank 46 as "CCB_L1A".
    CCB_L1A_RLS    : out std_logic;                        --! CCB L1A release. Fixed to '0' in ODMB2014 fw. Connected to bank 45.
    CCB_CLKEN      : in  std_logic;                        --! CCB clock enable signal. Connected to ODMB CTRL in ODMB2014 fw but unused. Connected to bank 46.
    CCB_EVCNTRES_B : in  std_logic;                        --! CCB event counter reset. Used by simulated FE boards. Connected to bank 64 as "CCB_EVCNTRES".
    CCB_HARDRST_B  : in  std_logic;                        --! CCB hard reset. Unusable since hard reset resets the FPGA but must be input to avoid self-reset. Connected to bank 45 in error.
    CCB_SOFT_RST_B : in  std_logic;                        --! CCB soft reset. Triggers reset of elements throughout firmware. Connected to bank 45 as "CCB_SOFT_RST".

    --------------------
    -- LVMB Signals
    --------------------
    LVMB_PON     : out std_logic_vector(7 downto 0);       --! Signal to LVMB to power on (x)DCFEBs and ALCT. Mapping of bits to boards is chamber dependent. Used by ODMB_VME. Connected to bank 67.
    PON_LOAD_B   : out std_logic;                          --! Signal to write LVMB_PON to LVMB. Used by ODMB_VME. Connected to bank 67.
    PON_OE       : out std_logic;                          --! Output enable for LVMB_PON. Fixed to '1'. Used by ODMB_VME. Connected to bank 67.
    MON_LVMB_PON : in  std_logic_vector(7 downto 0);       --! Signal to check (x)DCFEBs and ALCT power status from LVMB. Mapping of bits to boards is chamber dependent. Used by ODMB_VME. Connected to bank 67.
    LVMB_CSB     : out std_logic_vector(6 downto 0);       --! LVMB ADC SPI chip select. Used by ODMB_VME. Connected to bank 67.
    LVMB_SCLK    : out std_logic;                          --! LVMB ADC SPI clock. Used by ODMB_VME. Connected to bank 68.
    LVMB_SDIN    : out std_logic;                          --! LVMB ADC SPI input. Used by ODMB_VME. Connected to bank 68.
    LVMB_SDOUT_P : in std_logic;                           --! LVMB ADC SPI output. Used by ODMB_VME. Connected to bank 67 as C_LVMB_SDOUT_P.
    LVMB_SDOUT_N : in std_logic;                           --! LVMB ADC SPI output. Used by ODMB_VME. Connected to bank 67 as C_LVMB_SDOUT_N.

    --------------------------------
    -- OTMB communication signals
    --------------------------------
    OTMB            : in  std_logic_vector(35 downto 0);   --! OTMB data. Used for packet building and PRBS test. Connected to bank 44-45 as "TMB[35:0]".
    RAWLCT          : in  std_logic_vector(7 downto 0);    --! Local charged track signals, used by TRGCNTRL in ODMB CTRL for timing and for PRBS test. Connected to bank 45 (to be updated).
    OTMB_DAV        : in  std_logic;                       --! OTMB data available used by TRGCNTRL in ODMB CTRL for timing. Connected to bank 45 as TMB_DAV.
    LEGACY_ALCT_DAV : in  std_logic;                       --! ALCT data available used by TRGCNTRL in ODMB CTRL for timing. Connected to bank 45 as RSVTD[7] (to be updated).
    OTMB_FF_CLK     : in  std_logic;                       --! Unused. Connected to bank 45 as TMB_FF_CLK.
    RSVTD           : in  std_logic_vector(5 downto 3);    --! Reserved to DMB signals used only for OTMB PRBS test. Connected to bank 44-45 as RSVTD[7:3] (to be updated).
    RSVFD           : out std_logic_vector(3 downto 1);    --! Reserved to DMB signals used to send L1A info to OTMB and for PRBS test. Connected to bank 44-45 as RSVTD[2:0] (to be updated).
    LCT_RQST        : out std_logic_vector(2 downto 1);    --! Used to send LCT and external trigger requests generated by ODMB_VME and for PRBS test. Connected to bank 45.

    --------------------------------
    -- ODMB JTAG
    --------------------------------
    KUS_TMS       : out std_logic;                         --! JTAG TMS signal to ODMB FPGA, used by ODMBJTAG in ODMB_VME. Connected to bank 47.
    KUS_TCK       : out std_logic;                         --! JTAG TCK signal to ODMB FPGA, used by ODMBJTAG in ODMB_VME. Connected to bank 47.
    KUS_TDI       : out std_logic;                         --! JTAG TDI signal to ODMB FPGA, used by ODMBJTAG in ODMB_VME. Connected to bank 47.
    KUS_TDO       : in std_logic;                          --! JTAG TDO signal from ODMB FPGA, used by ODMBJTAG in ODMB_VME. Connected to bank 47 as TDO (pin U9).
    KUS_DL_SEL    : out std_logic;                         --! ODMB JTAG path select, connected to ODMBJTAG module in ODMB_VME. Use 1 for DL/red box and 0 for firmware communication. Connected to bank 47.

    --------------------------------
    -- ODMB optical ports
    --------------------------------
    -- Acutally connected optical TX/RX signals
    DAQ_RX_P     : in std_logic_vector(10 downto 0);       --! R12 optical RX from FE boards.
    DAQ_RX_N     : in std_logic_vector(10 downto 0);       --! R12 optical RX from FE boards.
    DAQ_SPY_RX_P : in std_logic;                           --! R12 optical RX from FE boards (DAQ_RX_P11) or finisar RX SPY_RX_P.
    DAQ_SPY_RX_N : in std_logic;                           --! R12 optical RX from FE boards (DAQ_RX_N11) or finisar RX SPY_RX_N.
    B04_RX_P     : in std_logic_vector(4 downto 2);        --! B04 optical RX from FED. No use yet.
    B04_RX_N     : in std_logic_vector(4 downto 2);        --! B04 optical RX from FED. No use yet.
    BCK_PRS_P    : in std_logic;                           --! B04 optical RX from FED for backpressure (B04_RX1_P).
    BCK_PRS_N    : in std_logic;                           --! B04 optical RX from FED for backpressure (B04_RX1_N).

    SPY_TX_P     : out std_logic;                          --! Finisar (spy) optical TX output to PC.
    SPY_TX_N     : out std_logic;                          --! Finisar (spy) optical TX output to PC.
    DAQ_TX_P     : out std_logic_vector(1 downto 1);       --! Temporary: B04 optical TX1, output to ALCT.
    DAQ_TX_N     : out std_logic_vector(1 downto 1);       --! Temporary: B04 optical TX1, output to ALCT.
    -- DAQ_TX_P     : out std_logic_vector(4 downto 1);    --! B04 optical TX, output to FED.
    -- DAQ_TX_N     : out std_logic_vector(4 downto 1);    --! B04 optical TX, output to FED.

    --------------------------------
    -- Optical control signals
    --------------------------------
    DAQ_SPY_SEL    : out std_logic;                        --! Multiplexor control. 0 to select DAQ_RX_P/N11, 1 to select SPY_RX_P/N.

    RX12_I2C_ENA   : out std_logic;                        --! I2C enable for RX12 firefly, currently tied to 0. Connected to bank 66.
    RX12_SDA       : inout std_logic;                      --! I2C serial data signal to/from RX12 firefly, currently unused. Connected to bank 66.
    RX12_SCL       : inout std_logic;                      --! I2C serial clock signal to RX12 firefly, currently unused. Connected to bank 66.
    RX12_CS_B      : out std_logic;                        --! I2C chip select signal to RX12 firefly, tied to '1'. Connected to bank 66.
    RX12_RST_B     : out std_logic;                        --! Reset signal to RX12 firefly, tied to '1'. Connected to bank 66.
    RX12_INT_B     : in std_logic;                         --! Interrupt (fault) signal from RX12 firefly, currently unused. Connected to bank 66.
    RX12_PRESENT_B : in std_logic;                         --! Present signal from RX12 firefly, currently unused. Connected to bank 66.

    TX12_I2C_ENA   : out std_logic;                        --! I2C enable for TX12 firefly, currently tied to 0. Connected to bank 66.
    TX12_SDA       : inout std_logic;                      --! I2C serial data signal to/from TX12 firefly, currently unused. Connected to 66.
    TX12_SCL       : inout std_logic;                      --! I2C serial clock signal to TX12 firefly, currently unused. Connected to bank 66.
    TX12_CS_B      : out std_logic;                        --! I2C chip select signal to TX12 firefly, tied to '1'. Connected to bank 66.
    TX12_RST_B     : out std_logic;                        --! Reset signal to TX12 firefly, tied to '1'. Connected to bank 66.
    TX12_INT_B     : in std_logic;                         --! Interrupt (fault) signal from TX12 firefly, currently unused. Connected to bank 66.
    TX12_PRESENT_B : in std_logic;                         --! Present signal from TX12 firefly, currently unused. Connected to bank 66.

    B04_I2C_ENA   : out std_logic;                         --! I2C enable for B04 firefly, currently tied to 0. Connected to bank 66.
    B04_SDA       : inout std_logic;                       --! I2C serial data signal to/from B04 firefly, currently unused. Connected to bank 66.
    B04_SCL       : inout std_logic;                       --! I2C serial clock signal to B04 firefly, currently unused. Connected to bank 66.
    B04_CS_B      : out std_logic;                         --! I2C chip select signal to B04 firefly, tied to '1'. Connected to bank 66.
    B04_RST_B     : out std_logic;                         --! Reset signal to B04 firefly, tied to '1'. Connected to bank 66.
    B04_INT_B     : in std_logic;                          --! Interrupt (fault) signal from B04 firefly, currently unused. Connected to bank 66.
    B04_PRESENT_B : in std_logic;                          --! Present signal from B04 firefly, currently unused. Connected to bank 66.

    SPY_I2C_ENA   : out std_logic;                         --! I2C enable for Finisar, currently unused. Connected to bank 66.
    SPY_SDA       : inout std_logic;                       --! I2C serial data to/from Finisar, currently unused. Connected to bank 66.
    SPY_SCL       : inout std_logic;                       --! I2C serial clock to Finisar, currently unused. Connected to bank 66.
    SPY_SD        : in std_logic;                          --! Finisar signal detect signal, currently unused. Connected to bank 66.
    SPY_TDIS      : out std_logic;                         --! Transmitter disable signal to Finisar, tied to '0'. Connected to bank 66.

    --------------------------------
    -- Essential selector/reset signals not classified yet
    --------------------------------
    FPGA_SEL      : out std_logic;                         --! Clock synthesizer control input selector, needs to be tied to '0'. Connected to bank 47.
    RST_CLKS_B    : out std_logic;                         --! Clock synthesizer reset signal, needs to be tied to '1'. Connected to bank 47.
    ODMB_DONE     : in std_logic;                          --! Kintex Ultrascale configuration DONE signal from DONE_0 in bank 0 (N7). Unused but needs to be input. Connected to bank 66 (pin L9).

    --------------------------------
    -- System monitoring ports
    --------------------------------
    SYSMON_P      : in std_logic_vector(15 downto 0);      --! Current monitoring analog signals from monitor ICs to SYSTEM_MON in VME module. Connected to bank 64.
    SYSMON_N      : in std_logic_vector(15 downto 0);      --! Current monitoring analog signals from monitor ICs to SYSTEM_MON in VME module. Connected to bank 64.
    ADC_CS_B      : out std_logic_vector(4 downto 0);      --! SPI chip select signals to voltage monitor ADCs used by SYSTEM_MON in VME module. Connected to bank 64.
    ADC_DIN       : out std_logic;                         --! SPI input signal to voltage monitor ADCs used by SYSTEM_MON in VME module. Connected to bank 64.
    ADC_SCK       : out std_logic;                         --! SPI clock signal to voltage monitor ADCs used by SYSTEM_MON in VME module. Connected to bank 64.
    ADC_DOUT      : in std_logic;                          --! SPI output signal from voltage monitor ADCs used by SYSTEM_MON in VME module. Connected to bank 64.

    --------------------------------
    -- PROM pins
    --------------------------------
    PROM_RST_B    : out std_logic;                         --! Reset signal to both PROM ICs currently tied to 1. Connected to bank 65.
    PROM_CS2_B    : out std_logic;                         --! Chip select signal to secondary PROM, used by spi_interface in ODMB_VME. Connected to bank 65.
    CNFG_DATA     : inout std_logic_vector(7 downto 4);    --! Data signals to/from the secondary PROM, used by spi_interface in ODMB_VME. Connected to bank 65.

    --------------------------------
    -- Others
    --------------------------------
    LEDS_CFV      : out std_logic_vector(11 downto 0)      --! Front panel LEDs, currently unused. Connected to bank 65.
    );
end odmb7_ucsb_dev;

architecture Behavioral of odmb7_ucsb_dev is
  constant NCFEB  : integer range 1 to 7 := 7;  -- Number of DCFEBS, 7 for ODMB7

  component ila_gbt is
    port (
      clk: in std_logic;
      probe0: in std_logic_vector(111 downto 0);
      probe1: in std_logic_vector(71 downto 0);
      probe2: in std_logic_vector(31 downto 0);
      probe3: in std_logic
      );
  end component;


  component ila_db is
    port (
      clk: in std_logic;
      probe0: in std_logic_vector(3 downto 0);
      probe1: in std_logic_vector(31 downto 0);
      probe2: in std_logic_vector(79 downto 0);
      probe3: in std_logic_vector(83 downto 0);
      probe4: in std_logic_vector(31 downto 0)
      );
  end component;
  
  component fed_txdata_vio is
    port (
        clk: in std_logic;
        probe_out0: out std_logic_vector(83 downto 0);
        probe_out1: out std_logic;
        probe_out2: out std_logic;
        probe_out3: out std_logic;
        probe_out4: out std_logic_vector(31 downto 0)
    );
  end component;
  --------------------------------------
  -- Clock signals
  --------------------------------------
  signal mgtrefclk0_224 : std_logic;
  signal mgtrefclk0_225 : std_logic;
  signal mgtrefclk0_226 : std_logic;
  signal mgtrefclk1_226 : std_logic;
  signal mgtrefclk0_227 : std_logic;
  signal mgtrefclk1_227 : std_logic;
  signal sysclk625k : std_logic;
  signal sysclk1p25 : std_logic;
  signal sysclk2p5 : std_logic;
  signal sysclk10 : std_logic;
  signal sysclk20 : std_logic;
  signal sysclk40 : std_logic;
  signal sysclk80 : std_logic;
  signal cmsclk : std_logic;
  signal clk_lfclk : std_logic;
  signal clk_gp6 : std_logic;
  signal clk_gp7 : std_logic;
  signal mgtclk1 : std_logic;
  signal mgtclk2 : std_logic;
  signal mgtclk3 : std_logic;
  signal mgtclk4 : std_logic;
  signal mgtclk5 : std_logic;
  signal mgtclk125 : std_logic;

  --------------------------------------
  -- VME signals
  --------------------------------------
  signal vme_dir_b        : std_logic;
  signal vme_dir          : std_logic;
  signal vme_oe_b         : std_logic;
  signal vme_data_out_buf : std_logic_vector(15 downto 0) := (others => '0');
  signal vme_data_in_buf  : std_logic_vector(15 downto 0) := (others => '0');
  signal rst              : std_logic := '0'; --meta:uncomment_for_odmb

  --------------------------------------
  -- PPIB/DCFEB signals
  --------------------------------------
  signal dcfeb_tck    : std_logic_vector (NCFEB downto 1) := (others => '0');
  signal dcfeb_tms    : std_logic := '0';
  signal dcfeb_tdi    : std_logic := '0';
  signal dcfeb_tdo    : std_logic_vector (NCFEB downto 1) := (others => '0');
  signal gen_dcfeb_tdo : std_logic_vector (NCFEB downto 1) := (others => '0');
  signal dcfeb_tdo_int : std_logic_vector (NCFEB downto 1) := (others => '0');

  --------------------------------------
  -- ODMB JTAG signals
  --------------------------------------
  signal odmb_initjtag     : std_logic := '0';

  --------------------------------------
  -- Certain reset signals
  --------------------------------------
  signal reset_pulse        : std_logic := '0';
  signal reset_pulse_q      : std_logic := '0';
  signal l1acnt_rst         : std_logic := '0';
  signal l1acnt_rst_meta    : std_logic := '0';
  signal l1acnt_rst_sync    : std_logic := '0';
  signal l1a_reset_pulse    : std_logic := '0';
  signal l1a_reset_pulse_q  : std_logic := '0';
  signal opt_reset_pulse    : std_logic := '0';
  signal opt_reset_pulse_q  : std_logic := '0';
  signal premask_injpls     : std_logic := '0';
  signal premask_extpls     : std_logic := '0';
  signal dcfeb_injpls       : std_logic := '0';
  signal dcfeb_extpls       : std_logic := '0';
  signal test_bc0           : std_logic := '0';
  signal pre_bc0            : std_logic := '0';
  signal dcfeb_bc0          : std_logic := '0';
  signal dcfeb_resync       : std_logic := '0';
  signal dcfeb_l1a          : std_logic := '0';
  signal masked_l1a         : std_logic := '0';
  signal odmbctrl_l1a       : std_logic := '0';
  signal dcfeb_l1a_match    : std_logic_vector(NCFEB downto 1) := (others => '0');
  signal masked_l1a_match   : std_logic_vector(NCFEB downto 1) := (others => '0');
  signal odmbctrl_l1a_match : std_logic_vector(NCFEB downto 1) := (others => '0');
  signal ccb_bx0            : std_logic := '0';
  signal ccb_bx0_q          : std_logic := '0';
  attribute clock_buffer_type : string;
  attribute clock_buffer_type of CCB_CMD        : signal is "NONE";
  attribute clock_buffer_type of CCB_CMD_S      : signal is "NONE";
  attribute clock_buffer_type of CCB_DATA       : signal is "NONE";
  attribute clock_buffer_type of CCB_DATA_S     : signal is "NONE";
  attribute clock_buffer_type of CCB_CAL        : signal is "NONE";
  attribute clock_buffer_type of CCB_CRSV       : signal is "NONE";
  attribute clock_buffer_type of CCB_DRSV       : signal is "NONE";
  attribute clock_buffer_type of CCB_RSVO       : signal is "NONE";
  attribute clock_buffer_type of CCB_RSVI       : signal is "NONE";
  attribute clock_buffer_type of CCB_BX0_B      : signal is "NONE";
  attribute clock_buffer_type of CCB_BX_RST_B   : signal is "NONE";
  attribute clock_buffer_type of CCB_L1A_RST_B  : signal is "NONE";
  attribute clock_buffer_type of CCB_L1A_B      : signal is "NONE";
  attribute clock_buffer_type of CCB_L1A_RLS    : signal is "NONE";
  attribute clock_buffer_type of CCB_CLKEN      : signal is "NONE";
  attribute clock_buffer_type of CCB_EVCNTRES_B : signal is "NONE";

  -- signals to generate dcfeb_initjtag when DCFEBs are done programming
  signal pon_rst_reg        : std_logic_vector(31 downto 0) := x"00FFFFFF";
  signal pon_reset          : std_logic := '0';
  signal done_cnt_en        : std_logic_vector(NCFEB downto 1);
  signal done_cnt_rst       : std_logic_vector(NCFEB downto 1);
  signal done_cnt           : t_done_cnt_arr(NCFEB downto 1);
  signal done_next_state    : t_done_state_arr(NCFEB downto 1);
  signal done_current_state : t_done_state_arr(NCFEB downto 1);
  signal dcfeb_done_pulse   : std_logic_vector(NCFEB downto 1) := (others => '0');
  signal dcfeb_initjtag     : std_logic := '0';
  signal dcfeb_initjtag_d   : std_logic := '0';
  signal dcfeb_initjtag_dd  : std_logic := '0';

  --------------------------------------
  -- CCB production test signals
  --------------------------------------
  signal ccb_cmd_bxev    : std_logic_vector(7 downto 0) := (others => '0');
  signal ccb_rsv         : std_logic_vector(10 downto 0) := (others => '0');
  signal ccb_other       : std_logic_vector(10 downto 0) := (others => '0');

  --------------------------------------
  -- LVMB signals
  --------------------------------------
  signal lvmb_sdout : std_logic := '0';

  --------------------------------------
  -- Triggers
  --------------------------------------
  signal test_lct    : std_logic := '0';
  signal test_l1a    : std_logic := '0';
  signal raw_l1a     : std_logic := '0';
  signal raw_lct     : std_logic_vector(NCFEB downto 0);
  signal int_alct_dav, tc_alct_dav : std_logic;
  signal int_otmb_dav, tc_otmb_dav : std_logic;
  signal otmb_push_dly_p1, alct_push_dly_p1        : integer range 0 to 64;
  signal tc_lct                    : std_logic_vector(NCFEB-1 downto 0);
  signal alct_dav_sync_out, otmb_dav_sync_out : std_logic;

  --------------------------------------
  -- Internal configuration signals
  --------------------------------------
  signal mask_pls         : std_logic := '0';
  signal mask_l1a         : std_logic_vector(NCFEB downto 0) := (others => '0');
  signal lct_l1a_dly      : std_logic_vector(5 downto 0) := (others => '0');
  signal inj_dly          : std_logic_vector(4 downto 0) := (others => '0');
  signal ext_dly          : std_logic_vector(4 downto 0) := (others => '0');
  signal callct_dly       : std_logic_vector(3 downto 0) := (others => '0');
  signal cable_dly        : integer range 0 to 1;
  signal odmb_ctrl_reg    : std_logic_vector(15 downto 0) := (others => '0');
  signal kill             : std_logic_vector(NCFEB+2 downto 1) := (others => '0');
  signal change_reg_data  : std_logic_vector(15 downto 0);
  signal change_reg_index : integer range 0 to NREGS := NREGS;
  signal bx_dly           : integer range 0 to 4095;
  signal crateid          : std_logic_vector(7 downto 0);

  --------------------------------------
  -- ODMB VME <=> ODMB CTRL signals
  --------------------------------------
  signal test_inj : std_logic := '0';
  signal test_pls : std_logic := '0';
  signal test_ped : std_logic := '0';

  --------------------------------------
  -- EEPROM signals
  --------------------------------------
  signal cnfg_data_in    : std_logic_vector(7 downto 4) := (others => '0');
  signal cnfg_data_out   : std_logic_vector(7 downto 4) := (others => '0');
  signal cnfg_data_dir   : std_logic_vector(7 downto 4) := (others => '0');

  --------------------------------------
  -- Reset signals
  --------------------------------------
  signal fw_reset        : std_logic := '0';
  signal fw_reset_q      : std_logic := '0';
  signal opt_reset       : std_logic := '0';
  signal opt_reset_q     : std_logic := '0';
  signal ccb_softrst_b_q : std_logic := '1';
  signal fw_rst_reg      : std_logic_vector(31 downto 0) := (others => '0');
  signal opt_rst_reg     : std_logic_vector(31 downto 0) := (others => '0');
  signal reset           : std_logic := '0';

  --------------------------------------
  -- MGT PRBS signals as place holder
  --------------------------------------
  signal mgt_prbs_type : std_logic_vector(3 downto 0);

  signal dcfeb_prbs_fiber_sel : std_logic_vector(3 downto 0);
  signal dcfeb_prbs_en : std_logic;
  signal dcfeb_prbs_rst : std_logic;
  signal dcfeb_prbs_rd_en : std_logic;
  signal dcfeb_rxprbserr :  std_logic;

  --------------------------------------
  -- SPY channel signals
  --------------------------------------
  constant SPY_SEL : std_logic := '1';

  signal usrclk_spy_tx : std_logic; -- USRCLK for TX data preparation
  signal usrclk_spy_rx : std_logic; -- USRCLK for RX data readout
  signal spy_rx_n : std_logic;
  signal spy_rx_p : std_logic;
  signal spy_txready : std_logic; -- Flag for tx reset done
  signal spy_rxready : std_logic; -- Flag for rx reset done
  signal spy_txdata : std_logic_vector(15 downto 0);  -- Data to be transmitted
  signal spy_txd_valid : std_logic;   -- Flag for tx data valid
  signal spy_txdiffctrl : std_logic_vector(3 downto 0);   -- Controls the TX voltage swing
  signal spy_loopback : std_logic_vector(2 downto 0);   -- For internal loopback tests
  signal spy_rxdata : std_logic_vector(15 downto 0);  -- Data received
  signal spy_rxd_valid : std_logic;   -- Flag for valid data;
  signal spy_bad_rx : std_logic;   -- Flag for fiber errors;
  signal spy_reset : std_logic;

  signal spy_prbs_tx_en : std_logic;
  signal spy_prbs_rx_en : std_logic;
  signal spy_prbs_tst_cnt : std_logic_vector(15 downto 0);
  signal spy_prbs_err_cnt : std_logic_vector(15 downto 0) := (others => '0');

  --------------------------------------
  -- MGT signals for FED channels
  --------------------------------------
  constant FED_NTXLINK   : integer := 1;
  constant FED_NRXLINK   : integer := 1;

  signal usrclk_fed_tx   : std_logic_vector(1 to FED_NTXLINK); -- USRCLK for TX data preparation
  signal fed_txclken     : std_logic_vector(1 to FED_NTXLINK); -- CLKEN signal for the USRCLK of TX data preparation
  signal fed_txdata_gbt  : t_std84_array(1 to FED_NTXLINK);   -- Data to be transmitted
  signal fed_txdata_wb   : t_std32_array(1 to FED_NTXLINK);   -- Data received
  signal fed_txd_valid   : std_logic_vector(1 to FED_NTXLINK);   -- Flag for tx valid data;
  signal fed_mgt_txready : std_logic_vector(1 to FED_NTXLINK); -- Flag for rx reset done
  signal fed_gbt_txready : std_logic_vector(1 to FED_NTXLINK); -- Flag for rx reset done
  signal fed_txready     : std_logic_vector(1 to FED_NTXLINK); -- Flag for rx reset done

  signal usrclk_fed_rx   : std_logic_vector(1 to FED_NRXLINK); -- USRCLK for RX data readout
  signal fed_rxclken     : std_logic_vector(1 to FED_NRXLINK); -- CLKEN signal for the USRCLK of RX data readout
  signal fed_rxdata_gbt  : t_std84_array(1 to FED_NRXLINK);   -- Data received
  signal fed_rxdata_wb   : t_std32_array(1 to FED_NRXLINK);   -- Data received
  signal fed_rxd_valid   : std_logic_vector(1 to FED_NRXLINK);   -- Flag for rx valid data;
  signal fed_bad_rx      : std_logic_vector(1 to FED_NRXLINK);   -- Flag for fiber errors;
  signal fed_rxready     : std_logic_vector(1 to FED_NRXLINK); -- Flag for rx reset done
  signal fed_mgt_rxready : std_logic_vector(1 to FED_NRXLINK); -- Flag for rx reset done
  signal fed_gbt_rxready : std_logic_vector(1 to FED_NRXLINK); -- Flag for rx reset done
  signal fed_reset       : std_logic;

  signal fed_prbs_tx_en : std_logic_vector(4 downto 1);
  signal fed_prbs_rx_en : std_logic_vector(4 downto 1);
  signal fed_prbs_tst_cnt : std_logic_vector(15 downto 0);
  signal fed_prbs_err_cnt : std_logic_vector(15 downto 0);

  signal ila_data_mgt_fed : std_logic_vector(83 downto 0);
  signal opt_reset_fed_from_vio  : std_logic := '0';
  signal fed_tx_isdata_from_vio  : std_logic := '0';
  signal fed_txdata_from_vio    : std_logic_vector(83 downto 0) := (others => '0');
  signal fed_txdata_wb_from_vio    : std_logic_vector(31 downto 0) := (others => '0');
  --------------------------------------
  -- MGT signals for DCFEB RX channels
  --------------------------------------
  signal usrclk_mgtc : std_logic;
  signal dcfeb_rxdata : t_std16_array(NCFEB downto 1);  -- Data received
  signal dcfeb_rxd_valid : std_logic_vector(NCFEB downto 1);   -- Flag for valid data;
  signal dcfeb_crc_valid : std_logic_vector(NCFEB downto 1);   -- Flag for valid data;
  signal dcfeb_bad_rx : std_logic_vector(NCFEB downto 1);   -- Flag for fiber errors;
  signal dcfeb_rxready : std_logic; -- Flag for rx reset done
  signal mgtc_reset : std_logic;

  signal dcfeb_prbs_rx_en : std_logic_vector(NCFEB downto 1);
  signal dcfeb_prbs_tst_cnt : std_logic_vector(15 downto 0);
  signal dcfeb_prbs_err_cnt :  std_logic_vector(15 downto 0) := (others => '0');

  -- Place holder signals for dcfeb data FIFOs
  signal dcfeb_datafifo_full : std_logic_vector(NCFEB downto 1) := (others => '0');
  signal dcfeb_datafifo_afull : std_logic_vector(NCFEB downto 1) := (others => '0');

  --------------------------------------
  -- MGT signals for ALCT RX channels
  --------------------------------------
  signal usrclk_mgta       : std_logic; -- User clock for ALCT, at 120 MHz
  signal alct_rxclken      : std_logic; -- Clock enable signal, on for every third clock of the usrclk
  signal alct_rxdata       : std_logic_vector(71 downto 0);  -- Data received from ALCT
  signal alct_rxdata_remap : std_logic_vector(111 downto 0); -- Raw widebus reordered data
  signal alct_rxd_valid    : std_logic; -- Flag for valid data
  signal alct_mgt_rxready  : std_logic; -- Flag for valid mgt status
  signal alct_gbt_rxready  : std_logic; -- Flag for valid gbt sync status
  signal alct_rxready      : std_logic; -- Flag combined of previous two
  signal alct_bad_rx       : std_logic; -- Flag for bad receiver packet / fiber error

  signal ila_data_alct     : std_logic_vector(31 downto 0);  -- Data received from ALCT
  signal ila_data_fed0 : std_logic_vector(111 downto 0); -- ILA data related to FED
  signal ila_data_fed1 : std_logic_vector(71 downto 0);  -- ILA data related to FED
  
  -- signal alct_prbs_rx_en : std_logic_vector(ALCT_NLINK-1 downto 0);
  signal alct_prbs_tst_cnt : std_logic_vector(15 downto 0);
  signal alct_prbs_err_cnt : std_logic_vector(15 downto 0) := (others => '0');

  signal mgt_reset : std_logic := '0';
  
  signal ila_data_mgt_alct : std_logic_vector(83 downto 0);
  signal opt_reset_alct_from_vio  : std_logic := '0';
  signal alct_raw_gbt       : std_logic_vector(83 downto 0);
  signal alct_raw_wb       : std_logic_vector(31 downto 0);
  
  --------------------------------------
  -- Miscellaneous
  --------------------------------------
  signal nwords_dummy  : std_logic_vector(15 downto 0);

  --------------------------------------
  -- Debug signals
  --------------------------------------
  signal diagout_inner : std_logic_vector(17 downto 0) := (others => '0');

  --------------------------------------
  -- DAQ related signals
  --------------------------------------
  signal odmb_status_data : std_logic_vector(15 downto 0) := (others => '0');
  signal odmb_status_sel  : std_logic_vector(7 downto 0) := (others => '0');
  signal bxcnt_rst        : std_logic := '0';
  signal ccb_l1acnt_rst   : std_logic := '0';
  signal ccb_l1acnt_rst_q : std_logic := '0';
  signal ccb_bxrst_b_q    : std_logic := '0';
  signal cafifo_l1a       : std_logic := '0';
  signal cafifo_l1a_match_in : std_logic_vector(NCFEB+2 downto 1);
  signal cafifo_l1a_match_out : std_logic_vector(NCFEB+2 downto 1);
  signal dcfeb_fifo_rst   : std_logic_vector(NCFEB downto 1);

  signal cafifo_prev_next_l1a_match : std_logic_vector(15 downto 0);
  signal cafifo_prev_next_l1a       : std_logic_vector(15 downto 0);
  signal cafifo_debug, control_debug : std_logic_vector(15 downto 0);
  signal cafifo_wr_addr              : std_logic_vector(7 downto 0);
  signal cafifo_rd_addr              : std_logic_vector(7 downto 0);
  signal cafifo_l1a_cnt       : std_logic_vector(23 downto 0);
  signal cafifo_l1a_dav       : std_logic_vector(NCFEB+2 downto 1);
  signal cafifo_bx_cnt        : std_logic_vector(11 downto 0);

  -- signal data_fifo_out       : t_std18_array(NCFEB+2 downto 1);
  -- signal data_fifo_dav       : std_logic_vector(NCFEB+2 downto 1);

  signal eof_data       : std_logic_vector(NCFEB+2 downto 1);
  signal into_fifo_dav  : std_logic_vector(NCFEB+2 downto 1);
  signal fifo_half_full : std_logic_vector(NCFEB+2 downto 1);
  signal fifo_empty     : std_logic_vector(NCFEB+2 downto 1);

  signal fifo_dout : std_logic_vector(17 downto 0);
  signal fifo_oe_b : std_logic_vector(NCFEB+2 downto 1) := (others => '1');
  signal fifo_re_b : std_logic_vector(NCFEB+2 downto 1) := (others => '1');

  signal ddu_data                : std_logic_vector(15 downto 0);
  signal ddu_data_valid, ddu_eof : std_logic;

  -- for TRGCNTRL
  constant push_dly    : integer := 63;  -- It needs to be > alct/otmb_push_dly
  signal alct_push_dly : integer range 0 to 63;
  signal otmb_push_dly : integer range 0 to 63;
  signal test_otmb_dav, test_alct_dav              : std_logic := '0';

begin

  -------------------------------------------------------------------------------------------
  -- Constant driver for selector/reset pins for board to work
  -------------------------------------------------------------------------------------------
  FPGA_SEL <= '0';
  RST_CLKS_B <= '1';

  -------------------------------------------------------------------------------------------
  -- Handle incoming data from OTMB/ALCT/DCFEBs
  -------------------------------------------------------------------------------------------
  MBD : entity work.odmb_data
    generic map (
      NCFEB               => NCFEB, 
      RUN4SCHEME          => 0  -- 0: ALCT data at OTMB[35:18], 1: ALCT from optical, 2: OTMB data at 36 bit
      )
    port map (
      CMSCLK              => cmsclk,
      DDUCLK              => usrclk_spy_tx,
      DCFEBCLK            => usrclk_mgtc,
      ALCTCLK             => usrclk_mgta,
      ALCT_RXCLKEN        => alct_rxclken,
      RESET               => reset,
      L1ACNT_RST          => l1acnt_rst,
      KILL                => kill,
      CAFIFO_L1A          => cafifo_l1a, -- from cafifo.vhd
      CAFIFO_L1A_MATCH_IN => cafifo_l1a_match_in, -- from cafifo.vhd
      DCFEB_L1A           => odmbctrl_l1a, -- for dcfeb in simulation
      DCFEB_L1A_MATCH     => odmbctrl_l1a_match, -- for dcfeb in simulation
      NWORDS_DUMMY        => nwords_dummy,

      DCFEB_TCK           => dcfeb_tck,
      DCFEB_TDO           => gen_dcfeb_tdo,
      DCFEB_TMS           => dcfeb_tms,
      DCFEB_TDI           => dcfeb_tdi,

      DCFEB_FIFO_RST      => "0000000", -- auto-kill related
      EOF_DATA            => eof_data,
      INTO_FIFO_DAV       => into_fifo_dav,

      OTMB_DATA_IN        => OTMB,
      ALCT_DATA_IN        => alct_rxdata,
      ALCT_DAV_IN         => alct_rxd_valid,
      DCFEB_DATA_IN       => dcfeb_rxdata,
      DCFEB_DAV_IN        => dcfeb_rxd_valid,

      GEN_DCFEB_SEL       => odmb_ctrl_reg(7),

      FIFO_RE_B           => fifo_re_b,
      FIFO_OE_B           => fifo_oe_b,
      FIFO_DOUT           => fifo_dout,
      FIFO_EMPTY          => fifo_empty,
      FIFO_HALF_FULL      => fifo_half_full
      );

  -------------------------------------------------------------------------------------------
  -- Handle clock synthesizer signals and generate clocks
  -------------------------------------------------------------------------------------------
  MBK : entity work.odmb_clocking
    port map (
      -- Input clock signals
      CMS_CLK_FPGA_P => CMS_CLK_FPGA_P,
      CMS_CLK_FPGA_N => CMS_CLK_FPGA_N,
      GP_CLK_6_P     => GP_CLK_6_P,
      GP_CLK_6_N     => GP_CLK_6_N,
      GP_CLK_7_P     => GP_CLK_7_P,
      GP_CLK_7_N     => GP_CLK_7_N,
      REF_CLK_1_P    => REF_CLK_1_P,
      REF_CLK_1_N    => REF_CLK_1_N,
      REF_CLK_2_P    => REF_CLK_2_P,
      REF_CLK_2_N    => REF_CLK_2_N,
      REF_CLK_3_P    => REF_CLK_3_P,
      REF_CLK_3_N    => REF_CLK_3_N,
      REF_CLK_4_P    => REF_CLK_4_P,
      REF_CLK_4_N    => REF_CLK_4_N,
      REF_CLK_5_P    => REF_CLK_5_P,
      REF_CLK_5_N    => REF_CLK_5_N,
      CLK_125_REF_P  => CLK_125_REF_P,
      CLK_125_REF_N  => CLK_125_REF_N,
      LF_CLK         => LF_CLK,
      -- Output clocks
      mgtrefclk0_224 => mgtrefclk0_224,
      mgtrefclk0_225 => mgtrefclk0_225,
      mgtrefclk0_226 => mgtrefclk0_226,
      mgtrefclk1_226 => mgtrefclk1_226,
      mgtrefclk0_227 => mgtrefclk0_227,
      mgtrefclk1_227 => mgtrefclk1_227,
      clk_sysclk625k => sysclk625k,
      clk_sysclk1p25 => sysclk1p25,
      clk_sysclk2p5  => sysclk2p5,
      clk_sysclk10   => sysclk10,
      clk_sysclk20   => sysclk20,
      clk_sysclk40   => sysclk40,
      clk_sysclk80   => sysclk80,
      clk_cmsclk     => cmsclk,
      clk_lfclk      => clk_lfclk,
      clk_gp6        => clk_gp6,
      clk_gp7        => clk_gp7,
      clk_mgtclk1    => mgtclk1,
      clk_mgtclk2    => mgtclk2,
      clk_mgtclk3    => mgtclk3,
      clk_mgtclk4    => mgtclk4,
      clk_mgtclk5    => mgtclk5,
      clk_mgtclk125  => mgtclk125
      );

  -------------------------------------------------------------------------------------------
  -- Handle VME signals
  -------------------------------------------------------------------------------------------

  -- Handle VME data direction and output enable lines
  KUS_VME_DIR <= not vme_dir_b;
  KUS_VME_OE_B <= vme_oe_b;

  GEN_VMEIO_16 : for I in 0 to 15 generate
  begin
    VME_BUF : IOBUF port map(O => vme_data_in_buf(I), IO => VME_DATA(I), I => vme_data_out_buf(I), T => vme_dir_b);
  end generate GEN_VMEIO_16;

  -------------------------------------------------------------------------------------------
  -- PROM signals
  -------------------------------------------------------------------------------------------
  PROM_RST_B <= '1';
  GEN_PROM_BUF: for I in 4 to 7 generate
  begin
    PROM_DATA_BUF : IOBUF port map(O => cnfg_data_in(I), IO => CNFG_DATA(I), I => cnfg_data_out(I), T => cnfg_data_dir(I));
  end generate GEN_PROM_BUF;

  -------------------------------------------------------------------------------------------
  -- Handle PPIB/DCFEB signals
  -------------------------------------------------------------------------------------------

  PPIB_OUT_EN_B <= '0'; -- always enable
  -- Handle DCFEB I/O buffers
  OB_DCFEB_TMS: OBUFDS port map (I => dcfeb_tms, O => DCFEB_TMS_P, OB => DCFEB_TMS_N);
  OB_DCFEB_TDI: OBUFDS port map (I => dcfeb_tdi, O => DCFEB_TDI_P, OB => DCFEB_TDI_N);
  OB_DCFEB_INJPLS: OBUFDS port map (I => dcfeb_injpls, O => INJPLS_P, OB => INJPLS_N);
  OB_DCFEB_EXTPLS: OBUFDS port map (I => dcfeb_extpls, O => EXTPLS_P, OB => EXTPLS_N);
  OB_DCFEB_RESYNC: OBUFDS port map (I => dcfeb_resync, O => RESYNC_P, OB => RESYNC_N);
  OB_DCFEB_BC0: OBUFDS port map (I => dcfeb_bc0, O => BC0_P, OB => BC0_N);
  OB_DCFEB_L1A: OBUFDS port map (I => dcfeb_l1a, O => L1A_P, OB => L1A_N);
  GEN_DCFEBJTAG_7 : for I in 1 to NCFEB generate
  begin
    OB_DCFEB_TCK: OBUFDS port map (I => dcfeb_tck(I), O => DCFEB_TCK_P(I), OB => DCFEB_TCK_N(I));
    IB_DCFEB_TDO: IBUFDS port map (O => dcfeb_tdo(I), I => DCFEB_TDO_P(I), IB => DCFEB_TDO_N(I));
    OB_DCFEB_L1A_MATCH: OBUFDS port map (I => dcfeb_l1a_match(I), O => L1A_MATCH_P(I), OB => L1A_MATCH_N(I));
  end generate GEN_DCFEBJTAG_7;

  --generate pulses if not masked
  dcfeb_injpls <= '0' when mask_pls = '1' else premask_injpls;
  dcfeb_extpls <= '0' when mask_pls = '1' else premask_extpls;

  dcfeb_tdo_int <= dcfeb_tdo when (odmb_ctrl_reg(7) = '0') else gen_dcfeb_tdo;

  --generate RESYNC, BC0, L1A, and L1A match signals to DCFEBs
  --synchronization of CCB signals and push button
  ccb_bx0   <= not CCB_BX0_B;
  FD_CCBBX0 : FD port map(Q => ccb_bx0_q, C => cmsclk, D => ccb_bx0);
  FD_CCBBX  : FD port map(Q => ccb_bxrst_b_q, C => cmsclk, D => ccb_bx_rst_b);
  bxcnt_rst <= not ccb_bxrst_b_q;

  RESETPULSE      : PULSE2SAME port map(DOUT => reset_pulse, CLK_DOUT => cmsclk, RST => '0', DIN => reset);
  FD_RESETPULSE_Q : FD port map (Q => reset_pulse_q,     C => cmsclk, D => reset_pulse);
  FD_L1APULSE_Q   : FD port map (Q => l1a_reset_pulse_q, C => cmsclk, D => l1a_reset_pulse);

  --TODO: fix l1acnt_rst, 20MHz clock using ccb_bx0, and all other effects thereof)
  --TODO: fix this logic, copied from ODMB because timing violations
  --l1acnt_rst <= clk20 and (l1a_reset_pulse or l1a_reset_pulse_q or reset_pulse or reset_pulse_q);
  proc_sync_l1acnt : process (cmsclk)
  begin
    if rising_edge(cmsclk) then
      l1acnt_rst <= (l1a_reset_pulse or l1a_reset_pulse_q or reset_pulse or reset_pulse_q);
      l1acnt_rst_meta <= l1acnt_rst;
      l1acnt_rst_sync <= l1acnt_rst_meta;
    end if;
  end process;

  pre_bc0    <= test_bc0 or ccb_bx0_q;
  masked_l1a <= '0' when mask_l1a(0) = '1' else odmbctrl_l1a;

  DS_RESYNC : DELAY_SIGNAL generic map (NCYCLES_MAX => 1) port map (DOUT => dcfeb_resync, CLK => cmsclk, NCYCLES => cable_dly, DIN => l1acnt_rst);
  DS_BC0    : DELAY_SIGNAL generic map (NCYCLES_MAX => 1) port map (DOUT => dcfeb_bc0,    CLK => cmsclk, NCYCLES => cable_dly, DIN => pre_bc0   );
  DS_L1A    : DELAY_SIGNAL generic map (NCYCLES_MAX => 1) port map (DOUT => dcfeb_l1a,    CLK => cmsclk, NCYCLES => cable_dly, DIN => masked_l1a);

  GEN_DCFEB_L1A_MATCH : for I in 1 to NCFEB generate
  begin
    masked_l1a_match(I) <= '0' when mask_l1a(I) = '1' else odmbctrl_l1a_match(I);
    DS_L1A_MATCH : DELAY_SIGNAL generic map (NCYCLES_MAX => 1) port map (DOUT => dcfeb_l1a_match(I), CLK => cmsclk, NCYCLES => cable_dly, DIN => masked_l1a_match(I));
  end generate GEN_DCFEB_L1A_MATCH;

  -- FSM to handle initialization when DONE received from DCFEBs
  -- Generate dcfeb_initjtag
  done_fsm_regs : process (done_next_state, pon_reset, sysclk10)
  begin
    for dev in 1 to NCFEB loop
      if (pon_reset = '1') then
        done_current_state(dev) <= DONE_LOW;
      elsif rising_edge(sysclk10) then
        done_current_state(dev) <= done_next_state(dev);
        if done_cnt_rst(dev) = '1' then
          done_cnt(dev) <= 0;
        elsif done_cnt_en(dev) = '1' then
          done_cnt(dev) <= done_cnt(dev) + 1;
        end if;
      end if;
    end loop;
  end process;

  done_fsm_logic : process (done_current_state, DCFEB_DONE, done_cnt)
  begin
    for dev in 1 to NCFEB loop
      case done_current_state(dev) is
        when DONE_IDLE =>
          done_cnt_en(dev)      <= '0';
          dcfeb_done_pulse(dev) <= '0';
          if (DCFEB_DONE(dev) = '0') then
            done_next_state(dev) <= DONE_LOW;
            done_cnt_rst(dev)    <= '1';
          else
            done_next_state(dev) <= DONE_IDLE;
            done_cnt_rst(dev)    <= '0';
          end if;

        when DONE_LOW =>
          done_cnt_en(dev)      <= '0';
          dcfeb_done_pulse(dev) <= '0';
          done_cnt_rst(dev)     <= '0';
          if (DCFEB_DONE(dev) = '1') then
            done_next_state(dev) <= DONE_COUNTING;
          else
            done_next_state(dev) <= DONE_LOW;
          end if;

        when DONE_COUNTING =>
          if (DCFEB_DONE(dev) = '0') then
            done_next_state(dev)  <= DONE_LOW;
            done_cnt_en(dev)      <= '0';
            dcfeb_done_pulse(dev) <= '0';
            done_cnt_rst(dev)     <= '1';
          elsif (done_cnt(dev) = 3) then  -- DONE has to be high at least 400 us to avoid spurious edges
            done_next_state(dev)  <= DONE_IDLE;
            done_cnt_en(dev)      <= '0';
            dcfeb_done_pulse(dev) <= '1';
            done_cnt_rst(dev)     <= '0';
          else
            done_next_state(dev)  <= DONE_COUNTING;
            done_cnt_en(dev)      <= '1';
            dcfeb_done_pulse(dev) <= '0';
            done_cnt_rst(dev)     <= '0';
          end if;
      end case;
    end loop;
  end process;

  dcfeb_initjtag_dd <= or_reduce(dcfeb_done_pulse);
  -- FIXME: currently doesn't do anything because state machine pulses dcfeb_done_pulse for 1 40 MHz clock cycle, 10kHz on real board
  DS_DCFEB_INITJTAG    : DELAY_SIGNAL generic map(10) port map(DOUT => dcfeb_initjtag_d, CLK => sysclk625k, NCYCLES => 10, DIN => dcfeb_initjtag_dd);
  PULSE_DCFEB_INITJTAG : NPULSE2FAST port map(DOUT => dcfeb_initjtag, CLK_DOUT => sysclk1p25, RST => '0', NPULSE => 5, DIN => dcfeb_initjtag_d);

  -------------------------------------------------------------------------------------------
  -- Handle LVMB signals
  -------------------------------------------------------------------------------------------

  IB_LVMB_SDOUT: IBUFDS port map (O => lvmb_sdout, I => LVMB_SDOUT_P, IB => LVMB_SDOUT_N);

  -------------------------------------------------------------------------------------------
  -- Handle Triggers and DAVs
  -------------------------------------------------------------------------------------------
  LCTDLY_GTRG : LCTDLY port map(DOUT => test_l1a, CLK => cmsclk, DELAY => lct_l1a_dly, DIN => test_lct);

  raw_lct <= (others => '1') when (test_lct = '1') else RAWLCT;
  raw_l1a <= '1' when test_l1a = '1' else not CCB_L1A_B;

  otmb_push_dly_p1 <= otmb_push_dly + 1;
  alct_push_dly_p1 <= alct_push_dly + 1;
  DS_OTMB_PUSH : DELAY_SIGNAL generic map (64)port map(DOUT=>test_otmb_dav, CLK=>cmsclk, NCYCLES=>otmb_push_dly_p1, DIN=>test_l1a);
  DS_ALCT_PUSH : DELAY_SIGNAL generic map (64)port map(DOUT=>test_alct_dav, CLK=>cmsclk, NCYCLES=>alct_push_dly_p1, DIN=>test_l1a);

  int_alct_dav <= '1' when test_alct_dav = '1' else LEGACY_ALCT_DAV;
                  --tc_alct_dav when (testctrl_sel = '1') else
  int_otmb_dav <= '1' when test_otmb_dav = '1' else OTMB_DAV;
                  --tc_otmb_dav when (testctrl_sel = '1') else

  -------------------------------------------------------------------------------------------
  -- Handle Internal configuration signals
  -------------------------------------------------------------------------------------------

  -- FIXME: should change with bad_dcfeb_pulse and good_dcfeb_pulse, currently, KILL must be updated manually via VME command
  change_reg_data <= x"0" & "000" & kill(9) & kill(8) & kill(7 downto 1);
  change_reg_index <= NREGS;

  -------------------------------------------------------------------------------------------
  -- Handle CCB production test
  -------------------------------------------------------------------------------------------
  -- Unused
  CCB_L1A_RLS <= '0';

  -- From CCB - for production tests
  ccb_cmd_bxev <= CCB_CMD & CCB_EVCNTRES_B & CCB_BX_RST_B;
  ccb_rsv      <= CCB_CRSV(3 downto 0) & CCB_DRSV(1 downto 0) & CCB_RSVO(4 downto 0);
  ccb_other    <= CCB_CAL(2 downto 0) & CCB_BX0_B & CCB_BX_RST_B & CCB_L1A_RST_B & CCB_L1A_B
                  & CCB_CLKEN & CCB_EVCNTRES_B & CCB_CMD_S & CCB_DATA_S;

  -------------------------------------------------------------------------------------------
  -- Handle reset signals
  -------------------------------------------------------------------------------------------

  FD_CCB_SOFTRST : FD generic map(INIT => '1') port map (Q => ccb_softrst_b_q, C => cmsclk, D => CCB_SOFT_RST_B);

  FD_FW_RESET : FD port map (Q => fw_reset_q, C => cmsclk, D => fw_reset);
  fw_rst_reg <= x"3FFFF000" when ((fw_reset_q = '0' and fw_reset = '1') or ccb_softrst_b_q = '0') else
                fw_rst_reg(30 downto 0) & '0' when rising_edge(cmsclk) else
                fw_rst_reg;

  -- original: reset <= fw_rst_reg(31) or pon_rst_reg(31) or not pb0_q;
  -- pon_rst_reg used to be reset from pll lock
  pon_rst_reg <= pon_rst_reg(30 downto 0) & '0' when rising_edge(cmsclk) else
                 pon_rst_reg;
  pon_reset <= pon_rst_reg(31);

  reset <= fw_rst_reg(31) or pon_rst_reg(31);   -- Firmware reset

  FD_OPT_RESET : FD port map(Q => opt_reset_pulse_q, C => cmsclk, D => opt_reset_pulse);
  opt_rst_reg <= x"3FFFF000" when (opt_reset_pulse_q = '0' and opt_reset_pulse = '1') else
                 opt_rst_reg(30 downto 0) & '0' when rising_edge(cmsclk) else
                 opt_rst_reg;
  opt_reset <= opt_rst_reg(31) or pon_reset or mgt_reset;  -- Optical reset

  -------------------------------------------------------------------------------------------
  -- Sub-modules
  -------------------------------------------------------------------------------------------

  MBV : entity work.ODMB_VME
    generic map (
      NCFEB => NCFEB
      )
    port map (
      CLK160         => mgtclk1,
      CLK40          => cmsclk,
      CLK10          => sysclk10,
      CLK2P5         => sysclk2p5,
      CLK1P25        => sysclk1p25,

      VME_DATA_IN    => vme_data_in_buf,
      VME_DATA_OUT   => vme_data_out_buf,
      VME_GAP_B      => VME_GAP_B,
      VME_GA_B       => VME_GA_B,
      VME_ADDR       => VME_ADDR,
      VME_AM         => VME_AM,
      VME_AS_B       => VME_AS_B,
      VME_DS_B       => VME_DS_B,
      VME_LWORD_B    => VME_LWORD_B,
      VME_WRITE_B    => VME_WRITE_B,
      VME_IACK_B     => VME_IACK_B,
      VME_BERR_B     => VME_BERR_B,
      VME_SYSFAIL_B  => VME_SYSFAIL_B,
      VME_DTACK_B    => VME_DTACK_KUS_B,
      VME_OE_B       => vme_oe_b,
      VME_DIR_B      => vme_dir_b,      -- to be used in IOBUF

      DCFEB_TCK      => dcfeb_tck,
      DCFEB_TMS      => dcfeb_tms,
      DCFEB_TDI      => dcfeb_tdi,
      DCFEB_TDO      => dcfeb_tdo,
      DCFEB_DONE     => DCFEB_DONE,
      DCFEB_INITJTAG => dcfeb_initjtag,
      DCFEB_REPROG_B => DCFEB_REPROG_B,

      ODMB_TCK      => KUS_TCK,
      ODMB_TMS      => KUS_TMS,
      ODMB_TDI      => KUS_TDI,
      ODMB_TDO      => KUS_TDO,
      ODMB_SEL      => KUS_DL_SEL,
      ODMB_INITJTAG => odmb_initjtag,

      LVMB_PON    => LVMB_PON,
      PON_LOAD_B  => PON_LOAD_B,
      PON_OE      => PON_OE,
      R_LVMB_PON  => MON_LVMB_PON,
      LVMB_CSB    => LVMB_CSB,
      LVMB_SCLK   => LVMB_SCLK,
      LVMB_SDIN   => LVMB_SDIN,
      LVMB_SDOUT  => lvmb_sdout,

      OTMB        => OTMB,
      RAWLCT      => RAWLCT,
      OTMB_DAV    => OTMB_DAV,
      ALCT_DAV    => LEGACY_ALCT_DAV,
      OTMB_FF_CLK => OTMB_FF_CLK,
      RSVTD       => RSVTD,
      RSVFD       => RSVFD,
      LCT_RQST    => LCT_RQST,

      FW_RESET => fw_reset,
      L1A_RESET_PULSE => l1a_reset_pulse,
      OPT_RESET_PULSE => opt_reset_pulse,
      TEST_INJ => test_inj,
      TEST_PLS => test_pls,
      TEST_BC0 => test_bc0,
      TEST_PED => test_ped,
      TEST_LCT => test_lct,
      MASK_L1A => mask_l1a,
      MASK_PLS => mask_pls,
      ODMB_CAL => odmb_ctrl_reg(0),
      MUX_DATA_PATH => odmb_ctrl_reg(7),
      MUX_TRIGGER => odmb_ctrl_reg(9),
      MUX_LVMB => odmb_ctrl_reg(10),
      ODMB_PED => odmb_ctrl_reg(14 downto 13),
      ODMB_STAT_DATA => odmb_status_data,
      ODMB_STAT_SEL => odmb_status_sel,

      LCT_L1A_DLY      => lct_l1a_dly,
      CABLE_DLY        => cable_dly,
      OTMB_PUSH_DLY    => otmb_push_dly,
      ALCT_PUSH_DLY    => alct_push_dly,
      BX_DLY           => bx_dly,
      INJ_DLY          => inj_dly,
      EXT_DLY          => ext_dly,
      CALLCT_DLY       => callct_dly,
      ODMB_ID          => open,
      NWORDS_DUMMY     => nwords_dummy,
      KILL             => kill,
      CRATEID          => crateid,
      CHANGE_REG_DATA  => change_reg_data,
      CHANGE_REG_INDEX => change_reg_index,

      CNFG_DATA_IN     => cnfg_data_in,
      CNFG_DATA_OUT    => cnfg_data_out,
      CNFG_DATA_DIR    => cnfg_data_dir,
      PROM_CS2_B       => PROM_CS2_B,

      MGT_PRBS_TYPE        => mgt_prbs_type,
      FED_PRBS_TX_EN       => fed_prbs_tx_en,
      FED_PRBS_RX_EN       => fed_prbs_rx_en,
      FED_PRBS_TST_CNT     => fed_prbs_tst_cnt,
      FED_PRBS_ERR_CNT     => fed_prbs_err_cnt,
      SPY_PRBS_TX_EN       => spy_prbs_tx_en,
      SPY_PRBS_RX_EN       => spy_prbs_rx_en,
      SPY_PRBS_TST_CNT     => spy_prbs_tst_cnt,
      SPY_PRBS_ERR_CNT     => spy_prbs_err_cnt,
      DCFEB_PRBS_FIBER_SEL => dcfeb_prbs_fiber_sel,
      DCFEB_PRBS_EN        => dcfeb_prbs_en,
      DCFEB_PRBS_RST       => dcfeb_prbs_rst,
      DCFEB_PRBS_RD_EN     => dcfeb_prbs_rd_en,
      DCFEB_RXPRBSERR      => dcfeb_rxprbserr,
      DCFEB_PRBS_ERR_CNT   => dcfeb_prbs_err_cnt,

      SYSMON_P             => SYSMON_P,
      SYSMON_N             => SYSMON_N,
      ADC_CS_B             => ADC_CS_B,
      ADC_DIN              => ADC_DIN,
      ADC_SCK              => ADC_SCK,
      ADC_DOUT             => ADC_DOUT,

      DIAGOUT   => diagout_inner,
      RST       => reset,
      PON_RESET => pon_reset
      );

  MBC : entity work.ODMB_CTRL
    generic map (
      NCFEB => NCFEB,
      CAFIFO_SIZE => 32
      )
    port map (
      DDUCLK    => usrclk_spy_tx,
      CMSCLK    => cmsclk,

      CCB_CMD      => ccb_cmd,
      CCB_CMD_S    => ccb_cmd_s,
      CCB_DATA     => ccb_data,
      CCB_DATA_S   => ccb_data_s,
      CCB_BX0_B    => ccb_bx0_b,
      CCB_BXRST_B  => ccb_bx_rst_b,
      CCB_L1ARST_B => ccb_l1a_rst_b,
      CCB_CLKEN    => ccb_clken,

      TEST_CCBINJ => test_inj,
      TEST_CCBPLS => test_pls,
      TEST_CCBPED => test_ped,

      LCT_L1A_DLY => lct_l1a_dly,
      INJ_DLY     => inj_dly,
      EXT_DLY     => ext_dly,
      CALLCT_DLY  => callct_dly,
      OTMB_PUSH_DLY => otmb_push_dly,
      ALCT_PUSH_DLY => alct_push_dly,
      PUSH_DLY      => push_dly,

      CAL_MODE => odmb_ctrl_reg(0),
      PEDESTAL => odmb_ctrl_reg(13),
      PEDESTAL_OTMB => odmb_ctrl_reg(14),

      RAW_L1A => raw_l1a,
      RAWLCT  => raw_lct,

      OTMB_DAV => int_otmb_dav,         -- lctdav1 - from J4
      ALCT_DAV => int_alct_dav,         -- lctdav2 - from J4

      DCFEB_INJPULSE  => premask_injpls,
      DCFEB_EXTPULSE  => premask_extpls,
      DCFEB_L1A       => odmbctrl_l1a,
      DCFEB_L1A_MATCH => odmbctrl_l1a_match,

      ALCT_DAV_SYNC_OUT => open,
      OTMB_DAV_SYNC_OUT => open,

      DIAGOUT => open,
      KILL    => kill,
      LCT_ERR => open,            -- To an LED in the original design

      BX_DLY     => bx_dly,
      L1ACNT_RST => l1acnt_rst,
      BXCNT_RST  => bxcnt_rst,
      RST        => reset,

      EOF_DATA   => eof_data,

      CAFIFO_PREV_NEXT_L1A_MATCH => cafifo_prev_next_l1a_match,
      CAFIFO_PREV_NEXT_L1A       => cafifo_prev_next_l1a,
      CONTROL_DEBUG              => control_debug,
      CAFIFO_DEBUG               => cafifo_debug,
      CAFIFO_WR_ADDR             => cafifo_wr_addr,
      CAFIFO_RD_ADDR             => cafifo_rd_addr,

      CAFIFO_L1A           => cafifo_l1a,
      CAFIFO_L1A_MATCH_IN  => cafifo_l1a_match_in,
      CAFIFO_L1A_MATCH_OUT => cafifo_l1a_match_out,
      CAFIFO_L1A_CNT       => cafifo_l1a_cnt,
      CAFIFO_L1A_DAV       => cafifo_l1a_dav,
      CAFIFO_BX_CNT        => cafifo_bx_cnt,

      -- To GigaLinks
      DDU_DATA            => ddu_data,
      DDU_DATA_VALID      => ddu_data_valid,

      -- For headers/trailers
      GA => vme_ga_b,
      CRATEID => crateid,
      AUTOKILLED_DCFEBS  => "0000000",

      -- From/To Data FIFOs
      FIFO_RE_B  => fifo_re_b,
      FIFO_OE_B  => fifo_oe_b,
      FIFO_DOUT  => fifo_dout,
      -- FIFO_EOF => fifo_eof,
      FIFO_EMPTY   => fifo_empty,  -- emptyf*(7 DOWNTO 1) - from FIFOs
      FIFO_HALF_FULL => fifo_half_full
      );


  -------------------------------------------------------------------------------------------
  -- Constant driver for firefly selector/reset pins
  -------------------------------------------------------------------------------------------

  MBS : entity work.odmb_status
    generic map (
      NCFEB => NCFEB
      )
    port map (
      ODMB_STAT_SEL    => odmb_status_sel,
      ODMB_STAT_DATA   => odmb_status_data,

      CMSCLK           => cmsclk,
      DDUCLK           => usrclk_spy_tx,
      DCFEBCLK         => usrclk_mgtc,

      DCFEB_CRC_VALID  => dcfeb_crc_valid,
      DCFEB_RXD_VALID  => dcfeb_rxd_valid,
      DCFEB_BAD_RX     => dcfeb_bad_rx,
      RAW_LCT          => raw_lct,
      OTMB_DAV         => int_otmb_dav,
      ALCT_DAV         => int_alct_dav,
      RAW_L1A          => raw_l1a,
      DCFEB_L1A        => odmbctrl_l1a,

      EOF_DATA         => eof_data,
      FIFO_RE_B        => fifo_re_b,
      INTO_FIFO_DAV    => into_fifo_dav,
      CAFIFO_L1A_MATCH => cafifo_l1a_match_in,
      CAFIFO_L1A_DAV   => cafifo_l1a_dav,
      CAFIFO_L1A_CNT   => cafifo_l1a_cnt,
      CAFIFO_BX_CNT    => cafifo_bx_cnt,

      CCB_CMD_BXEV     => ccb_cmd_bxev,
      CCB_CMD_S        => CCB_CMD_S,
      CCB_DATA         => CCB_DATA,
      CCB_DATA_S       => CCB_DATA_S,
      CCB_RSV          => ccb_rsv,
      CCB_OTHER        => ccb_other,

      L1ACNT_RST       => l1acnt_rst,
      PON_RESET        => pon_reset,
      RESET            => reset
      );

  -------------------------------------------------------------------------------------------
  -- Constant driver for firefly selector/reset pins
  -------------------------------------------------------------------------------------------
  RX12_I2C_ENA <= '0';
  RX12_CS_B <= '1';
  RX12_RST_B <= '1';
  TX12_I2C_ENA <= '0';
  TX12_CS_B <= '1';
  TX12_RST_B <= '1';
  B04_I2C_ENA <= '0';
  B04_CS_B <= '1';
  B04_RST_B <= '1';
  SPY_TDIS <= '0';

  -------------------------------------------------------------------------------------------
  -- Optical communication with the SPY ports
  -------------------------------------------------------------------------------------------
  DAQ_SPY_SEL <= SPY_SEL; -- set for constant
  spy_rx_n <= DAQ_SPY_RX_N when SPY_SEL = '1' else '0';
  spy_rx_p <= DAQ_SPY_RX_P when SPY_SEL = '1' else '0';

  -- Run3 format: sending DAQ data to DDU via the SPY ports
  GTH_DDU : entity work.mgt_spy
    port map (
      mgtrefclk       => mgtrefclk0_226, -- for 1.6 Gb/s DDU transmission, mgtrefclk1_226 is sourced from the 125 MHz crystal
      txusrclk        => usrclk_spy_tx,  -- 80 MHz for 1.6 Gb/s with 8b/10b encoding, 62.5 MHz for 1.25 Gb/s
      rxusrclk        => usrclk_spy_rx,
      sysclk          => cmsclk,    -- maximum DRP clock frequency 62.5 MHz for 1.25 Gb/s line rate
      spy_rx_n        => spy_rx_n,
      spy_rx_p        => spy_rx_p,
      spy_tx_n        => SPY_TX_N,
      spy_tx_p        => SPY_TX_P,
      txready         => spy_txready,
      rxready         => spy_rxready,
      txdata          => ddu_data, --spy_txdata,
      txd_valid       => ddu_data_valid, --spy_txd_valid,
      txdiffctrl      => spy_txdiffctrl,
      loopback        => spy_loopback,
      rxdata          => spy_rxdata,
      rxd_valid       => spy_rxd_valid,
      bad_rx          => spy_bad_rx,
      prbs_type       => mgt_prbs_type,
      prbs_tx_en      => spy_prbs_tx_en,
      prbs_rx_en      => spy_prbs_rx_en,
      prbs_tst_cnt    => spy_prbs_tst_cnt,
      prbs_err_cnt    => spy_prbs_err_cnt,
      reset           => opt_reset
      );

  -------------------------------------------------
  -- DCFEB receiver for ODMB7
  -------------------------------------------------
  GTH_DCFEB : entity work.mgt_cfeb
    generic map (
      NLINK        => 7,  -- number of links
      DATAWIDTH    => 16  -- user data width
      )
    port map (
      mgtrefclk    => mgtrefclk0_224,
      rxusrclk     => usrclk_mgtc,
      sysclk       => sysclk80,
      daq_rx_n     => DAQ_RX_N(6 downto 0),
      daq_rx_p     => DAQ_RX_P(6 downto 0),
      rxdata_cfeb  => dcfeb_rxdata,
      rxd_valid    => dcfeb_rxd_valid,
      crc_valid    => dcfeb_crc_valid,
      rxready      => dcfeb_rxready,
      bad_rx       => dcfeb_bad_rx,
      kill_rxout   => kill(7 downto 1),
      kill_rxpd    => (others => '0'),
      fifo_full    => dcfeb_datafifo_full,
      fifo_afull   => dcfeb_datafifo_afull,
      prbs_type    => mgt_prbs_type,
      prbs_rx_en   => dcfeb_prbs_rx_en,
      prbs_tst_cnt => dcfeb_prbs_tst_cnt,
      prbs_err_cnt => dcfeb_prbs_err_cnt,
      reset        => opt_reset_alct_from_vio
      );

  -------------------------------------------------
  -- ALCT receiver with GBT format for ODMB7
  -------------------------------------------------
  GTH_ALCT : entity work.gbt_alct
    port map (
      mgtrefclk    => mgtrefclk0_225,   -- 120.24 MHz
      cmsclk       => cmsclk,
      drpclk       => mgtclk4,
      rxusrclk     => usrclk_mgta,      -- 120.24 MHz
      rxclken      => alct_rxclken,
      daq_rx_n     => DAQ_RX_N(7),
      daq_rx_p     => DAQ_RX_P(7),
      rxdata       => alct_rxdata,
      rxd_valid    => alct_rxd_valid,
      alct_mgt_rxready      => alct_mgt_rxready,
      alct_gbt_rxready      => alct_gbt_rxready,
      bad_rx       => alct_bad_rx,
      kill         => '0',
      rxdata_remap => alct_rxdata_remap,
      reset        => opt_reset_alct_from_vio,

      rxdata_raw_gbt    => alct_raw_gbt,
      rxdata_raw_wb     => alct_raw_wb,
      ila_data_mgt => ila_data_mgt_alct
      );

  --===============================================--
  -- Temporary GBT sender to make ALCT GBTx locked --
  --===============================================--  
  GBT_FED : entity work.gbt_wrapper
    generic map(
      NUM_LINKS       => 1,
      LINK_TYPE       => 1,
      TX_ENCODING     => 0, -- Sending in GBT format
      RX_ENCODING     => 1  -- Receiving in Wide-bus format
      )
    port map (
      MGT_REFCLK      => mgtrefclk0_225,
      GBT_FRAMECLK    => cmsclk,  -- 40.079 MHz
      MGT_DRP_CLK     => mgtclk4, -- 120.24 MHz from mgtrefclk0_225

      GBT_TXUSRCLK_o  => usrclk_fed_tx,
      GBT_RXUSRCLK_o  => usrclk_fed_rx,
      GBT_TXCLKEN_o   => fed_txclken,           -- from pattern generator, to be evaluated
      GBT_RXCLKEN_o   => fed_rxclken,      -- to pattern checker, to be evaluated

      MGT_RX_P(1)     => BCK_PRS_P,
      MGT_RX_N(1)     => BCK_PRS_N,
      MGT_TX_P(1)     => DAQ_TX_P(1),
      MGT_TX_N(1)     => DAQ_TX_N(1),

      GBT_TXDATA_i(1) => fed_txdata_gbt(1),
      GBT_RXDATA_o(1) => fed_rxdata_gbt(1),
      WB_TXDATA_i(1)  => fed_txdata_wb(1),
      WB_RXDATA_o(1)  => fed_rxdata_wb(1),
      --TXD_VALID_i(1)  => fed_txd_valid(1),
      TXD_VALID_i(1)  => fed_tx_isdata_from_vio,
      RXD_VALID_o(1)  => fed_rxd_valid(1),

      MGT_TXREADY_o   => fed_mgt_txready,
      MGT_RXREADY_o   => fed_mgt_rxready,
      GBT_TXREADY_o   => fed_gbt_txready,
      GBT_RXREADY_o   => fed_gbt_rxready,
      GBT_BAD_RX_o    => fed_bad_rx,
      RESET_i         => opt_reset_fed_from_vio,
      
      ila_data_mgt => ila_data_mgt_fed
      );

  --fed_txdata_gbt(1) <= x"CAAABABEAC1DACDCFFFFF";
  fed_txdata_gbt(1) <= fed_txdata_from_vio;
  fed_txdata_wb(1)  <= fed_txdata_wb_from_vio;

  ila_data_alct(0) <= int_alct_dav;
  ila_data_alct(1) <= raw_l1a;
  ila_data_alct(2) <= cafifo_l1a_match_in(9);
  ila_data_alct(3) <= int_otmb_dav;
  ila_data_alct(4) <= alct_rxd_valid;
  ila_data_alct(5) <= alct_bad_rx;
  ila_data_alct(6) <= alct_mgt_rxready;
  ila_data_alct(7) <= alct_gbt_rxready;
  ila_data_alct(8) <= kill(8);


  ila_data_fed1(0) <= fed_txd_valid(1);
  ila_data_fed1(1) <= fed_rxd_valid(1);
  ila_data_fed1(2) <= fed_mgt_txready(1);
  ila_data_fed1(3) <= fed_mgt_rxready(1);
  ila_data_fed1(4) <= fed_gbt_txready(1);
  ila_data_fed1(5) <= fed_gbt_rxready(1);
  ila_data_fed1(6) <= fed_bad_rx(1);
  ila_data_fed1(7) <= fed_txclken(1);

  ila_data_fed0 <= fed_txdata_wb(1) & fed_txdata_gbt(1)(79 downto 0);


  ila_fed_db: ila_db
    port map (
      clk => usrclk_fed_tx(1),
      probe0 => fed_txdata_gbt(1)(83 downto 80),
      probe1 => fed_txdata_wb(1),
      probe2 => fed_txdata_gbt(1)(79 downto 0),
      probe3 => ila_data_mgt_fed,
      probe4 => ila_data_fed1(31 downto 0)
      );


  ila_alct_db: ila_db
    port map (
      clk => usrclk_mgta,
      probe0 => alct_raw_gbt(83 downto 80),
      probe1 => alct_raw_wb,
      probe2 => alct_raw_gbt(79 downto 0),
      probe3 => ila_data_mgt_alct,
      probe4 => ila_data_alct
      );      


  ila_alct_rx : ila_gbt
    port map (
      clk => usrclk_mgta,
      probe0 => alct_rxdata_remap,
      probe1 => alct_rxdata,
      probe2 => ila_data_alct,
      probe3 => alct_rxclken
      );

  
  ila_fed_rx : ila_gbt
    port map (
      clk => usrclk_fed_tx(1),
      probe0 => ila_data_fed0,
      probe1 => ila_data_fed1,
      probe2 => fed_txdata_gbt(1)(31 downto 0),
      probe3 => fed_txclken(1)
      );

  vio : fed_txdata_vio 
    port map (
        clk => cmsclk,
        probe_out0 => fed_txdata_from_vio,
        probe_out1 => fed_tx_isdata_from_vio,
        probe_out2 => opt_reset_fed_from_vio,
        probe_out3 => opt_reset_alct_from_vio,       
        probe_out4 => fed_txdata_wb_from_vio
   ); 
      
end Behavioral;
