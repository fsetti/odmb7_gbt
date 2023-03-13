------------------------------------------------------------------------
--   This module provides an interface for SPI communication with
--   an EPROM. It uses the Xilinx STARTUPE3 module to output 
--   to the normal data, clock, and chip select lines and contains
--   processes to generate the appropriate commands.
--
------------------------------------------------------------------------

library ieee;
Library UNISIM;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
use UNISIM.vcomponents.all;
use work.ucsb_types.all;

--! @brief Module that directly generates SPI signals for post-startup communication with EPROMS
entity spi_interface is
  port
  (
    CLK                     : in std_logic; --! 40 MHz clock input
    RST                     : in std_logic; --! Soft reset signal
    ------------------ Signals to FIFO
    WRITE_FIFO_INPUT        : in std_logic_vector(15 downto 0); --! Data to write to programming FIFO
    WRITE_FIFO_WRITE_ENABLE : in std_logic;                     --! Write enable for programming FIFO
    ------------------ Address loading signals
    START_ADDRESS           : in std_logic_vector(31 downto 0); --! Address to start operation. Only bottom 3 bytes used
    START_ADDRESS_VALID     : in std_logic;                     --! Signal to load address
    ------------------ Commands
    WRITE_NWORDS            : in unsigned(11 downto 0);         --! Number of words to program
    START_WRITE             : in std_logic;                     --! Signal to begin programming
    OUT_WRITE_DONE          : out std_logic;                    --! '1' unless program in progress
    READ_NWORDS             : in unsigned(11 downto 0);         --! Number of words to read
    START_READ              : in std_logic;                     --! Signal to begin read
    OUT_READ_DONE           : out std_logic;                    --! '1' unless read in progress
    START_ERASE             : in std_logic;                     --! Signal to begin erase (1 sector)
    OUT_ERASE_DONE          : out std_logic;                    --! '1' unless erase in progress
    START_UNLOCK            : in std_logic;                     --! Signal to erase nonvolatile lock bits on all sectors
    OUT_UNLOCK_DONE         : out std_logic;                    --! '1' unless erase nonvolatile lock bits in progress
    START_LOCK              : in std_logic_vector(2 downto 0);  --! Signal to write lock bit - MSBs are 00 for nonvolatile 01 for volatile lock 1x for volatile unlock
    OUT_LOCK_DONE           : out std_logic;                    --! '1' unless write lock bits in progress
    START_READ_LOCK         : in std_logic_vector(1 downto 0);  --! Signal to read lock bit - MSB is 0 for nonvolatile 1 for volatile
    OUT_READ_LOCK_DONE      : out std_logic;                    --! '1' unless read lock bits in progress
    START_READ_ID           : in std_logic;                     --! Signal to read PROM ID
    OUT_READ_ID_DONE        : out std_logic;                    --! '1' unless read ID in progress
    START_CLEAR_STATUS      : in std_logic;                     --! Signal to clear status flag register
    OUT_CLEAR_STATUS_DONE   : out std_logic;                    --! '1' unless clear status flag in progress
    START_WRITE_REGISTER    : in std_logic_vector(3 downto 0);  --! Signal to write register, bit 3 indicates start and bits 2:0 indicate register
    OUT_WRITE_REGISTER_DONE : out std_logic;                    --! '1' unless write register in progress
    REGISTER_CONTENTS       : in std_logic_vector(15 downto 0); --! Register contents to be written with write register commands
    START_READ_REGISTER     : in std_logic_vector(3 downto 0);  --! Signal to start read register, when nonzero, indicates register
    OUT_READ_REGISTER_DONE  : out std_logic;                    --! '1' unless read register in progress
    OUT_REGISTER            : out std_logic_vector(7 downto 0); --! Contents of register read out
    OUT_REGISTER_WE         : out std_logic;                    --! Write enable for register
    START_CUSTOM            : in std_logic_vector(11 downto 0); --! Signal to start custom command where (11 downto 1) are number of bits to send and (0) is start
    CUSTOM_WORDS_TO_READ    : in std_logic_vector(15 downto 0); --! Number of bytes to read from custom command; should be set before START_CUSTOM(0)
    OUT_CUSTOM_DONE         : out std_logic;                    --! '1' unless custom SPI command in progress
    ------------------ Read output
    OUT_READ_DATA           : out std_logic_vector(15 downto 0); --! Data read out from PROM
    OUT_READ_DATA_VALID     : out std_logic;                     --! Indicates when data from PROM is valid
    ------------------ Signals to/from second EPROM
    PROM_SELECT             : in std_logic;                     --! Selector for which PROM is used (0=primary, 1=secondary)
    CNFG_DATA_IN            : in std_logic_vector(7 downto 4);  --! Data in from second EPROM
    CNFG_DATA_OUT           : out std_logic_vector(7 downto 4); --! Data out to second EPROM
    CNFG_DATA_DIR           : out std_logic_vector(7 downto 4); --! Tristate controller for second EPROM (1=to PROM)
    PROM_CS2_B              : out std_logic;                    --! Chip select for second EPROM
    ------------------ Debug
    DIAGOUT                 : out std_logic_vector(17 downto 0) --! Debug signals
   ); 	
end spi_interface;

architecture behavioral of spi_interface is
  attribute mark_debug : string;
  attribute dont_touch : string;
  attribute keep : string;
  attribute shreg_extract : string;
  attribute async_reg     : string;

component oneshot is
port (
  trigger: in  std_logic;
  clk : in std_logic;
  pulse: out std_logic
);
end component oneshot;
 
COMPONENT writeSpiFIFO
  PORT (
      srst : IN STD_LOGIC;
      wr_clk : IN STD_LOGIC;
      rd_clk : IN STD_LOGIC;
      din : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
      wr_en : IN STD_LOGIC;
      rd_en : IN STD_LOGIC;
      dout : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
      full : OUT STD_LOGIC;
      empty : OUT STD_LOGIC;
      prog_full : OUT STD_LOGIC;
      wr_rst_busy : OUT STD_LOGIC;
      rd_rst_busy : OUT STD_LOGIC
        );
END COMPONENT;

  -- SPI COMMAND ADDRESS WIDTH (IN BITS): Ensure setting is correct for the target flash
  constant  AddrWidth        : integer   := 32;  -- 24 or 32 (3 or 4 byte addr mode)
  -- SPI SECTOR SIZE (IN Bits)
  constant  SectorSize       : integer := 65536; -- 64K bits
  constant  SizeSector       : std_logic_vector(31 downto 0) := X"00010000"; -- 65536 bits
  constant  SubSectorSize    : integer := 4096; -- 4K bits
  constant  SizeSubSector    : std_logic_vector(31 downto 0) := X"00001000"; -- 4K bits
  constant  NumberofSectors  : std_logic_vector(8 downto 0) := "000000000";  -- 512 Sectors total
  constant  PageSize         : std_logic_vector(31 downto 0) := X"00000100"; -- 
  constant  NumberofPages    : std_logic_vector(16 downto 0) := "10000000000000000"; -- 256 bytes pages = 20000h
  constant  AddrStart32      : std_logic_vector(31 downto 0) := X"00000000"; -- First address in SPI
  constant  AddrEnd32        : std_logic_vector(31 downto 0) := X"01FFFFFF"; -- Last address in SPI (256Mb)
  -- SPI flash information
  constant  Idcode25NQ256    : std_logic_vector(23 downto 0) := X"20BB19";  -- RDID N256Q 256 MB
  
  -- Device command opcodes
  constant  CmdREAD24          : std_logic_vector(7 downto 0)  := X"03";
  constant  CmdFASTREAD        : std_logic_vector(7 downto 0)  := X"0B";
  constant  CmdREAD32          : std_logic_vector(7 downto 0)  := X"13";
  constant  CmdRDID            : std_logic_vector(7 downto 0)  := X"9F";
  constant  CmdRDFlashPara     : std_logic_vector(7 downto 0)  := X"5A";
  constant  CmdRDFR24Quad      : std_logic_vector(7 downto 0)  := X"0C";
  constant  CmdFLAGStatus      : std_logic_vector(7 downto 0)  := X"70";
  constant  CmdStatus          : std_logic_vector(7 downto 0)  := X"05";
  constant  CmdWE              : std_logic_vector(7 downto 0)  := X"06";
  constant  CmdSE24            : std_logic_vector(7 downto 0)  := X"D8";
  constant  CmdSE32            : std_logic_vector(7 downto 0)  := X"DC";
  constant  CmdSSE24           : std_logic_vector(7 downto 0)  := X"20";
  constant  CmdSSE32           : std_logic_vector(7 downto 0)  := X"21";
  constant  CmdPP24            : std_logic_vector(7 downto 0)  := X"02";
  constant  CmdPP32            : std_logic_vector(7 downto 0)  := X"12";
  constant  CmdPP24Quad        : std_logic_vector(7 downto 0)  := X"32"; 
  constant  CmdPP32Quad        : std_logic_vector(7 downto 0)  := X"34"; 
  constant  Cmd4BMode          : std_logic_vector(7 downto 0)  := X"B7";
  constant  CmdExit4BMode      : std_logic_vector(7 downto 0)  := X"E9";
  constant  CmdEraseNonvLock   : std_logic_vector(7 downto 0)  := X"E4";
  constant  CmdWriteNonvLock   : std_logic_vector(7 downto 0)  := X"E3";
  constant  CmdWriteVolaLock   : std_logic_vector(7 downto 0)  := X"E5";
  constant  CmdReadVolaLock    : std_logic_vector(7 downto 0)  := X"E8";
  constant  CmdReadNonvLock    : std_logic_vector(7 downto 0)  := X"E2";
  constant  CmdWriteNonvConfig : std_logic_vector(7 downto 0)  := X"B1";
  constant  CmdWriteVolaConfig : std_logic_vector(7 downto 0)  := X"81";
  constant  CmdWriteExteConfig : std_logic_vector(7 downto 0)  := X"61";
  constant  CmdWriteStatus     : std_logic_vector(7 downto 0)  := X"01";
  constant  CmdReadNonvConf    : std_logic_vector(7 downto 0)  := X"B5";
  constant  CmdReadVolaConf    : std_logic_vector(7 downto 0)  := X"85";
  constant  CmdReadExteConf    : std_logic_vector(7 downto 0)  := X"65";
  constant  CmdClearFlagStatus : std_logic_vector(7 downto 0)  := X"50";

  ------------- STARTUPE3/SPI signals -------------------- 
  signal spi_miso         : std_logic;
  signal spi_mosi         : std_logic;
  signal spi_cs_bar       : std_logic;
  signal spi_cs_bar_input : std_logic := '1';
  signal spi_cs_bar_delay : std_logic := '1';
  signal di_out           : std_logic_vector(3 downto 0) := X"0";
  signal do_in            : std_logic_vector(3 downto 0) := "0000";
  signal qspi_io          : std_logic_vector(3 downto 1) := "111";
  signal dopin_ts         : std_logic_vector(3 downto 0) := "1110";
  
  ------------- Write FIFO signals -------------------- 
  signal write_fifo_output          : std_logic_vector(3 downto 0) := "0000";
  signal write_spi_fifo_read_enable : std_logic := '0';
  signal write_fifo_read_enable     : std_logic := '0';

  ------------- Read signals -------------------- 
  signal read_spi_cs_bar         : std_logic := '1';
  signal read_done               : std_logic := '1';
  signal read_word_limit         : unsigned(31 downto 0) := x"00000000";
  signal read_word_counter       : unsigned(31 downto 0) := x"00000000";
  signal read_data               : std_logic_vector(15 downto 0) := X"0000";
  signal read_data_valid         : std_logic := '0';
  signal read_data_counter       : std_logic_vector(3 downto 0) := "0000";
  signal read_address            : std_logic_vector(31 downto 0) := X"00000000";
  signal read_cmdcounter         : unsigned(5 downto 0) := "111111";
  signal read_cmdreg             : std_logic_vector(39 downto 0) := X"1111111111";

  ------------- Erase signals -------------------- 
  signal erase_spi_cs_bar       : std_logic := '1';
  signal erase_done             : std_logic := '1';
  signal erase_address          : std_logic_vector(31 downto 0) := x"00000000";
  signal erase_cmdcounter       : unsigned(5 downto 0) := "111111";
  signal erase_cmdreg           : std_logic_vector(39 downto 0) := x"1111111111";
  signal erase_status_bit_index : std_logic_vector(7 downto 0) := x"00";

  ------------- Write signals -------------------- 
  signal write_spi_cs_bar       : std_logic := '1';
  signal write_done             : std_logic := '1';
  signal write_address          : std_logic_vector(31 downto 0) := x"00000000";
  signal write_cmdcounter       : unsigned(5 downto 0) := "111111";
  signal write_cmdreg           : std_logic_vector(39 downto 0) := x"1111111111";
  signal write_word_limit       : unsigned(31 downto 0) := x"00000000";
  signal write_data_counter     : unsigned(1 downto 0) := "00";
  signal write_word_counter     : unsigned(31 downto 0) := x"00000000";
  signal write_status_bit_index : std_logic_vector(7 downto 0) := x"00";

  ------------- Erase lock signals -------------------- 
  signal erase_lock_spi_cs_bar       : std_logic := '1';
  signal erase_lock_done             : std_logic := '1';
  signal erase_lock_cmdcounter       : unsigned(5 downto 0) := "111111";
  signal erase_lock_cmdreg           : std_logic_vector(39 downto 0) := x"1111111111";
  signal erase_lock_status_bit_index : std_logic_vector(7 downto 0) := x"00";

  ------------- Write lock signals -------------------- 
  signal write_lock_spi_cs_bar       : std_logic := '1';
  signal write_lock_type             : std_logic_vector(2 downto 0) := "000";
  signal write_lock_address          : std_logic_vector(31 downto 0) := x"00000000";
  signal write_lock_address_volatile : std_logic_vector(31 downto 0) := x"00000000";
  signal write_lock_done             : std_logic := '1';
  signal write_lock_cmdcounter       : unsigned(5 downto 0) := "111111";
  signal write_lock_cmdreg           : std_logic_vector(39 downto 0) := x"1111111111";
  signal write_lock_status_bit_index : std_logic_vector(7 downto 0) := x"00";

  ------------- Read lock signals -------------------- 
  signal read_lock_spi_cs_bar       : std_logic := '1';
  signal read_lock_type             : std_logic_vector(1 downto 0) := "00";
  signal read_lock_address          : std_logic_vector(31 downto 0) := x"00000000";
  signal read_lock_address_volatile : std_logic_vector(31 downto 0) := x"00000000";
  signal read_lock_done             : std_logic := '0';
  signal read_lock_cmdcounter       : unsigned(5 downto 0) := "000000";
  signal read_lock_cmdreg           : std_logic_vector(39 downto 0) := x"0000000000";
  signal read_lock_data_counter     : unsigned(1 downto 0) := "00";
  signal read_lock_data             : std_logic_vector(15 downto 0) := x"0000";
  signal read_lock_data_valid       : std_logic := '0';

  ------------- Write config signals -------------------- 
  signal write_config_spi_cs_bar       : std_logic := '1';
  signal write_config_done             : std_logic := '1';
  signal write_config_cmdcounter       : unsigned(5 downto 0) := "111111";
  signal write_config_cmdreg           : std_logic_vector(39 downto 0) := x"1111111111";
  signal write_config_status_bit_index : std_logic_vector(7 downto 0) := x"00";
  signal write_register_type           : std_logic_vector(3 downto 0) := x"0";

  ------------- Read register signals -------------------- 
  signal read_register_spi_cs_bar      : std_logic := '1';
  signal read_register_done            : std_logic := '0';
  signal read_register_type            : std_logic_vector(3 downto 0) := x"0";
  signal read_register_bit_index       : std_logic_vector(7 downto 0) := x"00";
  signal read_register_cmdcounter      : unsigned(5 downto 0) := "111111";
  signal read_register_cmdreg          : std_logic_vector(39 downto 0) := x"1111111111";
  signal register_inner                : std_logic_vector(7 downto 0) := x"00";
  signal register_we                   : std_logic := '0';
  signal read_register_max_index       : std_logic_vector(7 downto 0) := x"00";

  ------------- Read ID signals -------------------- 
  signal read_id_spi_cs_bar      : std_logic := '1';
  signal read_id_done            : std_logic := '0';
  signal read_id_cmdcounter      : unsigned(5 downto 0) := "111111";
  signal read_id_cmdreg          : std_logic_vector(39 downto 0) := x"1111111111";
  signal read_id_data            : std_logic_vector(15 downto 0) := x"0000";
  signal read_id_data_valid      : std_logic := '0';
  signal read_id_data_counter    : unsigned(7 downto 0) := x"00";

  ------------- Clear status signals -------------------- 
  signal clear_status_spi_cs_bar      : std_logic := '1';
  signal clear_status_done            : std_logic := '0';
  signal clear_status_cmdcounter      : unsigned(5 downto 0) := "111111";
  signal clear_status_cmdreg          : std_logic_vector(39 downto 0) := x"1111111111";

  ------------- Custom SPI command signals -------------------- 
  signal custom_done             : std_logic := '1';
  signal custom_spi_cs_bar       : std_logic := '1';
  signal custom_fifo_read_enable : std_logic := '0';
  signal custom_nbits_write      : unsigned(10 downto 0) := "00000000000";
  signal custom_nwords_read      : unsigned(15 downto 0) := x"0000";
  signal custom_mosi             : std_logic := '0';
  signal custom_fifo_idx         : unsigned(1 downto 0) := "11";
  signal custom_data_counter     : unsigned(3 downto 0) := x"0";
  signal custom_data             : std_logic_vector(15 downto 0) := x"0000";
  signal custom_data_valid       : std_logic := '0';
  signal custom_first_read_cycle : std_logic := '0';
  constant custom_enable         : std_logic := '0'; --should be 0 in normal firmware versions to disallow unintended SPI commands

  --------------- select read command and address -------------------- 
  --signal CmdIndex    : std_logic_vector(3 downto 0) := "0001";  
  --signal CmdSelect    : std_logic_vector(7 downto 0) := x"FF";  
  --signal AddSelect: std_logic_vector(31 downto 0) := x"00000000";  -- 32 bit command/addr
  --------------- other signals/regs/counters  ------------------------
  --signal data_valid_cntr : std_logic_vector(2 downto 0) := "000";
  --signal rddata          : std_logic_vector(1 downto 0) := "00";
  --signal spi_wrdata      : std_logic_vector(31 downto 0) := X"00000000";
  --signal page_count      : std_logic_vector(17 downto 0) := "111111111111111111";
  --signal StatusDataValid : std_logic := '0';
  --   ------- erase ----------------------------
  --signal er_sector_count          : std_logic_vector(13 downto 0) := "00000000000001";    -- subsector count
  --signal erase_address   : std_logic_vector(31 downto 0) := X"00000000"; -- start addr of current sector
  --signal erase_start     : std_logic := '0';
  --signal er_data_valid_cntr       : std_logic_vector(2 downto 0) := "000";
  --signal er_rddata       : std_logic_vector(1 downto 0) := "00";
  --signal er_status       : std_logic_vector(1 downto 0) := "11";
  --signal erase_inprogress: std_logic := '0';
  ------------- FIFO signals  ---------------------
  --signal fifo_empty      : std_logic := '0';
  --signal fifo_full       : std_logic := '0';
  --signal fifo_almostfull : std_logic := '0';
  --signal fifo_almostempty : std_logic := '0';
  --signal fifo_unconned   : std_logic_vector(15 downto 0) := X"0000";
  ------- Misc signal
  --signal reset_design    : std_logic := '0';
  --signal wrerr           : std_logic := '0';
  --signal rderr           : std_logic := '0';
  ----  syncers
  ----  place sync regs close together and no SRLs
  --signal synced_fifo_almostfull : std_logic_vector(1 downto 0) := "00";
  --  attribute keep of synced_fifo_almostfull : signal is "true";
  --  attribute async_reg of synced_fifo_almostfull : signal is "true";   
  --  attribute shreg_extract of synced_fifo_almostfull : signal is "no";

  --signal synced_read : std_logic_vector(1 downto 0) := "00";
  --  attribute keep of synced_read : signal is "true";
  --  attribute async_reg of synced_read : signal is "true";   
  --  attribute shreg_extract of synced_read : signal is "no";

  --signal synced_erase : std_logic_vector(1 downto 0) := "00";
  --  attribute keep of synced_erase : signal is "true";
  --  attribute async_reg of synced_erase : signal is "true";   
  --  attribute shreg_extract of synced_erase : signal is "no";

  type write_states is
  (
    S_WRITE_IDLE, S_WRITE_ASSERT_CS_WRITE_ENABLE, S_WRITE_SHIFT_WRITE_ENABLE,  S_WRITE_ASSERT_CS_PROGRAM,
    S_WRITE_SHIFT_PROGRAM, S_WRITE_SHIFT_DATA, S_WRITE_ASSERT_CS_READ_STATUS, S_WRITE_SHIFT_READ_STATUS,
    S_WRITE_ASSERT_CS_READ_STATUS_2, S_WRITE_SHIFT_READ_STATUS_2
  );
  signal write_state  : write_states := S_WRITE_IDLE;

  type read_states is
  (
    S_READ_IDLE, S_READ_ASSERT_CS, S_READ_SHIFT_READ
  );
  signal read_state : read_states := S_READ_IDLE;
  
  type erase_states is
  (
    S_ERASE_IDLE, S_ERASE_ASSERT_CS_WRITE_ENABLE, S_ERASE_SHIFT_WRITE_ENABLE, S_ERASE_ASSERT_CS_ERASE,
    S_ERASE_SHIFT_ERASE, S_ERASE_ASSERT_CS_READ_STATUS, S_ERASE_SHIFT_READ_STATUS
  );
  signal erase_state  : erase_states := S_ERASE_IDLE;

  type erase_lock_states is
  (
    S_ERASE_LOCK_IDLE, S_ERASE_LOCK_ASSERT_CS_WRITE_ENABLE, S_ERASE_LOCK_SHIFT_WRITE_ENABLE, S_ERASE_LOCK_ASSERT_CS_ERASE_LOCK,
    S_ERASE_LOCK_SHIFT_ERASE_LOCK, S_ERASE_LOCK_ASSERT_CS_READ_STATUS, S_ERASE_LOCK_SHIFT_READ_STATUS
  );
  signal erase_lock_state  : erase_lock_states := S_ERASE_LOCK_IDLE;

  type write_lock_states is
  (
    S_WRITE_LOCK_IDLE, S_WRITE_LOCK_ASSERT_CS_WRITE_ENABLE, S_WRITE_LOCK_SHIFT_WRITE_ENABLE, S_WRITE_LOCK_ASSERT_CS_WRITE_LOCK,
    S_WRITE_LOCK_SHIFT_WRITE_LOCK, S_WRITE_LOCK_ASSERT_CS_READ_STATUS, S_WRITE_LOCK_SHIFT_READ_STATUS,
    S_WRITE_LOCK_ASSERT_CS_READ_STATUS_2, S_WRITE_LOCK_SHIFT_READ_STATUS_2
  );
  signal write_lock_state  : write_lock_states := S_WRITE_LOCK_IDLE;

  type write_config_states is
  (
    S_WRITE_CONFIG_IDLE, S_WRITE_CONFIG_ASSERT_CS_WRITE_ENABLE, S_WRITE_CONFIG_SHIFT_WRITE_ENABLE, S_WRITE_CONFIG_ASSERT_CS_WRITE_CONFIG,
    S_WRITE_CONFIG_SHIFT_WRITE_CONFIG, S_WRITE_CONFIG_ASSERT_CS_READ_STATUS, S_WRITE_CONFIG_SHIFT_READ_STATUS,
    S_WRITE_CONFIG_ASSERT_CS_READ_STATUS_2, S_WRITE_CONFIG_SHIFT_READ_STATUS_2
  );
  signal write_config_state  : write_config_states := S_WRITE_CONFIG_IDLE;

  type read_register_states is
  (
    S_READ_REGISTER_IDLE, S_READ_REGISTER_ASSERT_CS_READ, S_READ_REGISTER_SHIFT_READ
  );
  signal read_register_state : read_register_states := S_READ_REGISTER_IDLE;

  type read_id_states is
  (
    S_READ_ID_IDLE, S_READ_ID_ASSERT_CS_READ, S_READ_ID_SHIFT_READ
  );
  signal read_id_state : read_id_states := S_READ_ID_IDLE;

  type read_lock_states is
  (
    S_READ_LOCK_IDLE, S_READ_LOCK_ASSERT_CS_READ, S_READ_LOCK_SHIFT_READ
  );
  signal read_lock_state : read_lock_states := S_READ_LOCK_IDLE;

  type clear_status_states is
  (
    S_CLEAR_STATUS_IDLE, S_CLEAR_STATUS_ASSERT_CS, S_CLEAR_STATUS_SHIFT
  );
  signal clear_status_state : clear_status_states := S_CLEAR_STATUS_IDLE;

  type custom_states is
  (
    S_CUSTOM_IDLE, S_CUSTOM_ASSERT_CS, S_CUSTOM_SHIFT, S_CUSTOM_FLUSH_FIFO
  );
  signal custom_state : custom_states := S_CUSTOM_IDLE;

 begin
   
  ----------------------------------------------------------------------------
  -- Deal with signals to PROMs
  ----------------------------------------------------------------------------

  --Signals to PROM connected to bank 0 go through STARTUPE3 module
  STARTUPE3_inst : STARTUPE3
  port map (
          CFGCLK => open,
          CFGMCLK => open,
          EOS => open,
          DI => di_out,  -- inspi_miso D01 pin to Fabric
          PREQ => open,
          -- End outputs to fabric ports
          DO => do_in,
          DTS => dopin_ts,
          FCSBO => spi_cs_bar,
          FCSBTS =>  '0',
          GSR => '0',
          GTS => '0',
          KEYCLEARB => '1',
          PACK => '1',
          USRCCLKO => CLK,
          USRCCLKTS => '0',  -- Clk_ts,
          USRDONEO => '1',
          USRDONETS => '0'    
  );

  spi_miso <= di_out(1) when PROM_SELECT='0' else
              CNFG_DATA_IN(5);
  --CNFG_DATA_DIR <= not dopin_ts(3) & not dopin_ts(2) & not dopin_ts(1) & not dopin_ts(0);
  CNFG_DATA_DIR <= dopin_ts(3 downto 0);
  
  qspi_io(3 downto 1) <= write_fifo_output(3 downto 1) when rising_edge(CLK);

  --update chip select and MOSI on falling edges
  update_chipsel : process(CLK)
  begin
    if falling_edge(CLK) then
      do_in <= qspi_io(3 downto 1) & spi_mosi;
      CNFG_DATA_OUT <= qspi_io(3 downto 1) & spi_mosi;    
      if (PROM_SELECT='0') then
        spi_cs_bar <= spi_cs_bar_input;
        PROM_CS2_B <= '1';
      else
        spi_cs_bar <= '1';
        PROM_CS2_B <= spi_cs_bar_input;
      end if;
    end if;
  end process;
  
  mux_mosi : process(CLK)
  begin
    if rising_edge(CLK) then
      if (read_done = '0') then spi_mosi <= read_cmdreg(39);
      elsif (erase_done = '0') then spi_mosi <= erase_cmdreg(39);
      elsif (erase_lock_done = '0') then spi_mosi <= erase_lock_cmdreg(39);
      elsif (write_lock_done = '0') then spi_mosi <= write_lock_cmdreg(39);
      elsif (read_lock_done = '0') then spi_mosi <= read_lock_cmdreg(39);
      elsif (write_config_done = '0') then spi_mosi <= write_config_cmdreg(39);
      elsif (read_register_done = '0') then spi_mosi <= read_register_cmdreg(39);
      elsif (read_id_done = '0') then spi_mosi <= read_id_cmdreg(39);
      elsif (clear_status_done = '0') then spi_mosi <= clear_status_cmdreg(39);
      elsif (custom_done = '0') then spi_mosi <= custom_mosi;
      else 
        case write_state is
          when S_WRITE_SHIFT_DATA =>
            spi_mosi <= write_fifo_output(0);
          when others =>
            spi_mosi <= write_cmdreg(39);
        end case;
      end if;
    end if; --CLK
  end process mux_mosi;
  
  mux_cs_bar: process (CLK)
  begin
    if rising_edge(CLK) then
      if (read_done = '0') then spi_cs_bar_input <= read_spi_cs_bar;
      elsif (erase_done = '0') then spi_cs_bar_input <= erase_spi_cs_bar;
      elsif (erase_lock_done = '0') then spi_cs_bar_input <= erase_lock_spi_cs_bar;
      elsif (write_lock_done = '0') then spi_cs_bar_input <= write_lock_spi_cs_bar;
      elsif (read_lock_done = '0') then spi_cs_bar_input <= read_lock_spi_cs_bar;
      elsif (write_config_done = '0') then spi_cs_bar_input <= write_config_spi_cs_bar;
      elsif (read_register_done = '0') then spi_cs_bar_input <= read_register_spi_cs_bar;
      elsif (read_id_done = '0') then spi_cs_bar_input <= read_id_spi_cs_bar;
      elsif (clear_status_done = '0') then spi_cs_bar_input <= clear_status_spi_cs_bar;
      elsif (custom_done = '0') then spi_cs_bar_input <= custom_spi_cs_bar;
      else spi_cs_bar_input <= write_spi_cs_bar;
      end if;
    end if; --CLK
  end process mux_cs_bar;

-----------------------------  program word FIFO  --------------------------------------------------

writeFIFO_i : writeSpiFIFO
  PORT MAP (
    srst => RST,
    wr_clk => CLK,
    rd_clk => CLK,
    din => WRITE_FIFO_INPUT,
    wr_en => WRITE_FIFO_WRITE_ENABLE,
    rd_en => write_spi_fifo_read_enable,
    dout => write_fifo_output,
    full => open,
    empty => open,
    prog_full => open,
    wr_rst_busy => open,
    rd_rst_busy => open 
  );
write_spi_fifo_read_enable <= write_fifo_read_enable or custom_fifo_read_enable;

-----------------------------  pass output signals  --------------------------------------------------
--    readdone                <= read_done;
--    out_read_spi_cs_bar           <= read_spi_cs_bar;
--    out_spi_cs_bar            <= spi_cs_b; 
--    out_spi_mosi             <= spi_mosi; 
--    out_spi_miso             <= spi_miso; 
--    out_CmdSelect          <= CmdSelect;
--    out_spi_cs_bar_input        <= spi_cs_bar_input; 
--    --out_read_data_counter <= read_data_counter;
--    out_read_data_counter(2 downto 0) <= er_data_valid_cntr;
--    out_cmdreg <= cmdreg;
--    out_cmdcntr32 <= read_cmdcounter;
--
--    out_wrwrite_fifo_read_enable <= write_fifo_read_enable;
--
--    out_wr_statusdatavalid <= StatusDataValid;
--    out_wr_rddata <= rddata;
--    out_wr_spistatus <= spi_status; 

OUT_READ_DATA <= read_id_data when (read_id_done='0') else 
                 read_lock_data when (read_lock_done='0') else 
                 custom_data when (custom_done='0') else 
                 read_data;
OUT_READ_DATA_VALID <= read_id_data_valid when (read_id_done='0') else
                       read_lock_data_valid when (read_lock_done='0') else 
                       custom_data_valid when (custom_done='0') else
                       read_data_valid;
OUT_READ_DONE <= read_done;
OUT_ERASE_DONE <= erase_done;
OUT_WRITE_DONE <= write_done;
OUT_UNLOCK_DONE <= erase_lock_done;
OUT_LOCK_DONE <= write_lock_done;
OUT_READ_LOCK_DONE <= read_lock_done;
OUT_WRITE_REGISTER_DONE <= write_config_done;
OUT_READ_REGISTER_DONE <= read_register_done;
OUT_READ_ID_DONE <= read_id_done;
OUT_CLEAR_STATUS_DONE <= clear_status_done;
OUT_REGISTER <= register_inner;
OUT_REGISTER_WE <= register_we;
OUT_CUSTOM_DONE <= custom_done;

---------------------------------  PROM READ FSM  ----------------------------------------------
--CmdSelect <= CmdStatus when CmdIndex = x"1" else
--             CmdRDID   when CmdIndex = x"2" else
--             CmdRDFlashPara   when CmdIndex = x"3" else
--             --CmdRDFR24Quad  when CmdIndex = x"4" else
--             CmdFASTREAD    when CmdIndex = x"4" else
--             x"FF";

process_read : process (CLK)
  begin
  if rising_edge(CLK) then
  case read_state is 
   when S_READ_IDLE =>
        --when START_READ received, initiate read process
        read_spi_cs_bar <= '1';
        if (START_ADDRESS_VALID = '1') then read_address <= START_ADDRESS(23 downto 0) & x"00"; end if; --currently 3-byte addressing
        if (START_READ = '1') then 
          read_data_counter <= "0000";
          read_word_limit(31 downto 0) <= (x"00000" & READ_NWORDS(11 downto 0)) + 1; 
          read_data <= x"0000";
          read_state <= S_READ_ASSERT_CS;
          read_done <= '0';
        else
          read_done <= '1';
        end if;

   when S_READ_ASSERT_CS =>
        --assert cs_bar and prep FASTREAD command
        read_cmdcounter <= "101001";  -- 40 bits = 8 command + 24 address + 8 dummy (10 dummy?? why?)
        read_cmdreg <=  CmdFASTREAD & read_address; --fast read
        read_spi_cs_bar <= '0';
        read_state <= S_READ_SHIFT_READ;

   when S_READ_SHIFT_READ =>
        --shift FASTREAD command, address, dummy cycles, then data back
        if (read_cmdcounter /= 0) then 
           read_cmdcounter <= read_cmdcounter - 1;
           read_cmdreg <= read_cmdreg(38 downto 0) & '0';
        else
          --command+address+dummy cycles are finished shifting, shift data back
          read_data_counter <= read_data_counter + 1;
          read_data <= read_data(14 downto 0) & spi_miso;
          if (read_data_counter = 15) then
              read_data_valid <= '1';
              read_word_counter <= read_word_counter + 1;
          else
              read_data_valid <= '0';
          end if;
          if (read_word_counter = read_word_limit) then
            read_state <= S_READ_IDLE;   -- Done. All info read 
            read_done <= '1';
            read_word_counter <= x"00000000";
            read_data_counter <= "0000";
            read_spi_cs_bar <= '1';
          end if;  -- if rddata valid
        end if; -- cmdcounter /= 32

   end case;  
 end if;  --rising_edge(CLK)
end process process_read;

-------------------------------  ERASE PROM FSM  --------------------------------------------------
process_erase : process (CLK)
  begin
  if rising_edge(CLK) then
  case erase_state is 
   when S_ERASE_IDLE =>
        --when START_ERASE received, initiate erase process
        erase_spi_cs_bar <= '1';
        if (START_ADDRESS_VALID = '1') then erase_address <= START_ADDRESS(23 downto 0) & x"00"; end if; --currently 3-byte addressing
        if (START_ERASE = '1') then
          erase_done <= '0';
          erase_state <= S_ERASE_ASSERT_CS_WRITE_ENABLE;
        else
          erase_done <= '1';
        end if;
                       
   when S_ERASE_ASSERT_CS_WRITE_ENABLE =>
        --assert CS and prep write enable commmand
        erase_cmdcounter <= "000111"; --8 bits of command
        erase_cmdreg <=  CmdWE & X"00000000";
        erase_spi_cs_bar <= '0';
        erase_state <= S_ERASE_SHIFT_WRITE_ENABLE;
                  
   when S_ERASE_SHIFT_WRITE_ENABLE =>
         --shift write enable
         if (erase_cmdcounter /= 0) then 
           erase_cmdcounter <= erase_cmdcounter - 1;  
           erase_cmdreg <= erase_cmdreg(38 downto 0) & '0';
         else 
           erase_spi_cs_bar <= '1';
           erase_state <= S_ERASE_ASSERT_CS_ERASE;        
         end if;
                   
   when S_ERASE_ASSERT_CS_ERASE =>
        --assert CS and prepare for erase
        erase_spi_cs_bar <= '0';   
        erase_cmdreg <=  CmdSE24 & erase_address; 
        erase_cmdcounter <= "011111"; --32 bits: 8 command + 24 address
        erase_state <= S_ERASE_SHIFT_ERASE;
                      
   when S_ERASE_SHIFT_ERASE =>     
        --shift erase command
        if (erase_cmdcounter /= 0) then 
          erase_cmdcounter <= erase_cmdcounter - 1;
          erase_cmdreg <= erase_cmdreg(38 downto 0) & '0';
        else
          erase_spi_cs_bar <= '1';
          erase_state <= S_ERASE_ASSERT_CS_READ_STATUS;
        end if;
                                      
   when S_ERASE_ASSERT_CS_READ_STATUS =>
        --assert cs and prepare for read status
        erase_spi_cs_bar <= '0';   
        erase_status_bit_index <= x"00";
        erase_cmdcounter <= "001111"; --16 bits = 8 command + 8 to skip first read cycle
        erase_cmdreg <=  CmdStatus & X"00000000";  -- Read Status register
        erase_state <= S_ERASE_SHIFT_READ_STATUS;
                  
   when S_ERASE_SHIFT_READ_STATUS =>
        --shift read status command and read back status register
        if (erase_cmdcounter /= 0) then 
          erase_cmdcounter <= erase_cmdcounter - 1;
          erase_cmdreg <= erase_cmdreg(38 downto 0) & '0';
        else
          --once command is shifted and first read cycle skipped, check bit 0 on each cycle to see if done
          erase_status_bit_index <= erase_status_bit_index + 1;
          if (erase_status_bit_index = 0) then 
            --status(0) is write in progress flag bit
            --note: Hualin's firmware only checks this on bit 0 of the next cycle. Not sure if necessary
            if (spi_miso = '0' or in_simulation) then
              erase_state <= S_ERASE_IDLE;
              erase_done <= '1';
            end if;
            --erase_in_progress_bit <= spi_miso;
          end if;
        end if;
   end case;  
 end if;  -- Clk
end process process_erase;

-------------------------------  WRITE PROM FSM  --------------------------------------------------

process_write : process (CLK)
  begin
  if rising_edge(Clk) then
  case write_state is 
   when S_WRITE_IDLE =>
        write_spi_cs_bar <= '1';
        --initalize program process when START_WRITE received
        if (START_ADDRESS_VALID = '1') then write_address <= START_ADDRESS(23 downto 0) & x"00"; end if; --currently, 3-byte addressing
        if (START_WRITE = '1') then
          write_fifo_read_enable <= '0';
          write_word_limit <= (x"00000" & WRITE_NWORDS(11 downto 0)) + 1; 
          dopin_ts <= "1110";
          write_done <= '0';
          write_state <= S_WRITE_ASSERT_CS_WRITE_ENABLE;
        else
          write_done <= '1';
        end if;

   when S_WRITE_ASSERT_CS_WRITE_ENABLE =>
        --assert CS and prepare write enable command
        --if (page_count /= 0) then 
        --  if (synced_fifo_almostfull(1) = '1') then
        --    SpiCsB <= '0';
        --    write_state <= S_WR_WRCMD;
        --  end if;
        --else 
        --don't wait for fifo anymore?
        write_cmdcounter <= "000111";  -- 8 bits of command
        write_cmdreg <=  CmdWE & X"00000000";
        write_spi_cs_bar <= '0';
        write_state <= S_WRITE_SHIFT_WRITE_ENABLE;
        --end if;
                  
   when S_WRITE_SHIFT_WRITE_ENABLE =>
        --shift write enable command
        if (write_cmdcounter /= 0) then
          write_cmdcounter <= write_cmdcounter - 1;  
          write_cmdreg <= write_cmdreg(38 downto 0) & '0';
        else
          write_spi_cs_bar <= '1';
          write_state <= S_WRITE_ASSERT_CS_PROGRAM;
        end if;
                   
   when S_WRITE_ASSERT_CS_PROGRAM =>
        --assert CS and prepare fast page program command
        write_spi_cs_bar <= '0';
        write_data_counter <= "00";
        write_word_counter <= x"00000000";
        write_cmdreg <=  CmdPP24Quad & write_address;  -- Program Page at Current_Addr
        write_cmdcounter <= "011111"; --32 bits: 8 command + 24 address bits
        write_state <= S_WRITE_SHIFT_PROGRAM;
                                                 
   when S_WRITE_SHIFT_PROGRAM =>
        -- shift fast page program command
        if (write_cmdcounter /= 0) then 
          write_cmdcounter <= write_cmdcounter - 1;
          write_cmdreg <= write_cmdreg(38 downto 0) & '0';
        else 
          write_state <= S_WRITE_SHIFT_DATA;
          write_fifo_read_enable <= '1';
          dopin_ts <= "0000";
        end if;
                          
   when S_WRITE_SHIFT_DATA =>
        --shift the data to be programmed
        write_data_counter <= write_data_counter + 1;
        if (write_data_counter = 3) then
          --finished shifting 1 word
          write_address <= write_address + 1;
          write_word_counter <= write_word_counter + 1;
          if (((write_word_limit-1) = write_word_counter) or (write_address(7 downto 0) = 255)) then
            --finish shifting data when we reach word limit or hit the end of a page
            write_fifo_read_enable <= '0';
            write_spi_cs_bar <= '1'; --latched otherwise
            write_state <= S_WRITE_ASSERT_CS_READ_STATUS;
          else
            write_fifo_read_enable <= '1';
          end if;
        elsif (write_data_counter = 1) then
          --finished shifting 1 byte
          write_address <= write_address + 1;
          if (write_address(7 downto 0) = 255) then
            --finish shifting data when we reach word limit or hit the end of a page
            write_fifo_read_enable <= '0';
            write_spi_cs_bar <= '1'; --latched otherwise
            write_state <= S_WRITE_ASSERT_CS_READ_STATUS;
          else
            write_fifo_read_enable <= '1';
          end if;
        else
          write_fifo_read_enable <= '1';
        end if;
        
   when S_WRITE_ASSERT_CS_READ_STATUS =>
        -- assert CS and prep read status command
        -- this part is strange, if only do read status once, will get 11111111 always from miso
        write_fifo_read_enable <= '0';
        write_spi_cs_bar <= '0';
        dopin_ts <= "1110"; --latched otherwise
        write_cmdcounter <= "011111"; --16 bits: 8 command + 8 to skip the first cycle
        write_cmdreg <=  CmdStatus & X"00000000";
        write_state <= S_WRITE_SHIFT_READ_STATUS;
        
   when S_WRITE_SHIFT_READ_STATUS =>
        --shift read status command and read back status register
        if (write_cmdcounter /= 0) then 
          write_cmdcounter <= write_cmdcounter - 1;
          write_cmdreg <= write_cmdreg(38 downto 0) & '0';
        else
          write_spi_cs_bar <= '1';
          write_state <= S_WRITE_ASSERT_CS_READ_STATUS_2;
        end if; --write_cmdcounter = 

   when S_WRITE_ASSERT_CS_READ_STATUS_2 =>
        -- assert CS and prep read status command
        write_spi_cs_bar <= '0';
        write_cmdcounter <= "011111"; --16 bits: 8 command + 8 to skip the first cycle
        write_status_bit_index <= x"00";
        write_cmdreg <=  CmdStatus & X"00000000";
        write_state <= S_WRITE_SHIFT_READ_STATUS_2;

   when S_WRITE_SHIFT_READ_STATUS_2 =>
        --shift read status command and read back status register
        if (write_cmdcounter /= 0) then 
          write_cmdcounter <= write_cmdcounter - 1;
          write_cmdreg <= write_cmdreg(38 downto 0) & '0';
        else
          --once command is shifted and first read cycle skipped, check bit 0 on each cycle to see if done
          write_status_bit_index <= write_status_bit_index + 1;
          if (write_status_bit_index = 0) then 
            --status(0) is write in progress flag bit
            --note: Hualin's firmware only checks this on bit 0 of the next cycle. Not sure if necessary
            if (spi_miso = '0' or in_simulation) then
              write_spi_cs_bar <= '1';
              if (write_word_limit = write_word_counter) then
                write_state <= S_WRITE_IDLE;
                write_done <= '1';
              else 
                write_state <= S_WRITE_ASSERT_CS_WRITE_ENABLE;
              end if; --write_nwords_limit /= write_word_counter
            end if; --spi_miso = '0' or in_simulation
          end if; --write_status_bit_index = 0
        end if; --write_cmdcounter = 0

   --when S_WR_PPDONE =>
   --     dopin_ts <= "1110";
   --     SpiCsB <= '0';
   --     data_valid_cntr <= "000";
   --     cmdcounter <= "100111";
   --     write_state <= S_WR_PPDONE_WAIT;
   --                 
   --when S_WR_PPDONE_WAIT => 
   --     write_fifo_read_enable <= '0';  
   --     if (reset_design = '1') then write_state <= S_WR_IDLE;
   --     else 
   --       if (cmdcounter /= 31) then cmdcounter <= cmdcounter - 1; 
   --         cmdreg <= cmdreg(38 downto 0) & '0';
   --       else -- keep reading the status register
   --         data_valid_cntr <= data_valid_cntr + 1;  -- rolls over to 0
   --         rddata <= rddata(1) & spi_miso;  -- deser 1:8  
   --         --rddata <= rddata(1) & "0" ;  -- deser 1:8  
   --         if (data_valid_cntr = 7) then  -- catch status byte
   --           StatusDataValid <= '1';    -- copy WE and Write in progress one cycle after rddate
   --         else 
   --           StatusDataValid <= '0';
   --         end if;
   --         if (StatusDataValid = '1') then spi_status <= rddata; end if;  --  rddata valid from previous cycle
   --         if (spi_status = 0 or in_simulation) then    -- Done with page program
   --         --if spi_status = 1 then    -- Done with page program
   --           SpiCsB <= '1';   -- turn off SPI
   --           cmdcounter <= "100111";
   --           cmdreg <=  CmdWE & X"00000000";  -- Set WE bit
   --           data_valid_cntr <= "000";
   --           StatusDataValid <= '0';
   --           spi_status <= "11";
   --           page_count <= page_count - 1;
   --           write_state <= S_WR_ASSCS1;
   --         end if;  -- spi_status
   --       end if;  -- cmdcounter
   --     end if;  -- reset_design
                          
    end case;
   end if;  -- CLK
end process process_write;

-------------------------------  ERASE LOCK FSM  --------------------------------------------------
process_erase_lock : process (CLK)
  begin
  if rising_edge(CLK) then
  case erase_lock_state is 
   when S_ERASE_LOCK_IDLE =>
        --when START_ERASE received, initiate erase process
        erase_lock_spi_cs_bar <= '1';
        if (START_UNLOCK = '1') then
          erase_lock_done <= '0';
          erase_lock_state <= S_ERASE_LOCK_ASSERT_CS_WRITE_ENABLE;
        else
          erase_lock_done <= '1';
        end if;
                       
   when S_ERASE_LOCK_ASSERT_CS_WRITE_ENABLE =>
        --assert CS and prep write enable commmand
        erase_lock_cmdcounter <= "000111"; --8 bits of command
        erase_lock_cmdreg <=  CmdWE & X"00000000";
        erase_lock_spi_cs_bar <= '0';
        erase_lock_state <= S_ERASE_LOCK_SHIFT_WRITE_ENABLE;
                  
   when S_ERASE_LOCK_SHIFT_WRITE_ENABLE =>
         --shift write enable
         if (erase_lock_cmdcounter /= 0) then 
           erase_lock_cmdcounter <= erase_lock_cmdcounter - 1;  
           erase_lock_cmdreg <= erase_lock_cmdreg(38 downto 0) & '0';
         else 
           erase_lock_spi_cs_bar <= '1';
           erase_lock_state <= S_ERASE_LOCK_ASSERT_CS_ERASE_LOCK;        
         end if;
                   
   when S_ERASE_LOCK_ASSERT_CS_ERASE_LOCK =>
        --assert CS and prepare for erase nonvolatile lock bits
        erase_lock_spi_cs_bar <= '0';   
        erase_lock_cmdreg <=  CmdEraseNonvLock & x"00000000"; 
        erase_lock_cmdcounter <= "000111"; --8 bits
        erase_lock_state <= S_ERASE_LOCK_SHIFT_ERASE_LOCK;
                      
   when S_ERASE_LOCK_SHIFT_ERASE_LOCK =>     
        --shift erase nonvolatile lock bits command
        if (erase_lock_cmdcounter /= 0) then 
          erase_lock_cmdcounter <= erase_lock_cmdcounter - 1;
          erase_lock_cmdreg <= erase_lock_cmdreg(38 downto 0) & '0';
        else
          erase_lock_spi_cs_bar <= '1';
          erase_lock_state <= S_ERASE_LOCK_ASSERT_CS_READ_STATUS;
        end if;
                                      
   when S_ERASE_LOCK_ASSERT_CS_READ_STATUS =>
        --assert cs and prepare for read status
        erase_lock_spi_cs_bar <= '0';   
        erase_lock_status_bit_index <= x"00";
        erase_lock_cmdcounter <= "001111"; --16 bits = 8 command + 8 to skip first read cycle
        erase_lock_cmdreg <=  CmdStatus & X"00000000";  -- Read Status register
        erase_lock_state <= S_ERASE_LOCK_SHIFT_READ_STATUS;
                  
   when S_ERASE_LOCK_SHIFT_READ_STATUS =>
        --shift read status command and read back status register
        if (erase_lock_cmdcounter /= 0) then 
          erase_lock_cmdcounter <= erase_lock_cmdcounter - 1;
          erase_lock_cmdreg <= erase_lock_cmdreg(38 downto 0) & '0';
        else
          --once command is shifted and first read cycle skipped, check bit 0 on each cycle to see if done
          erase_lock_status_bit_index <= erase_lock_status_bit_index + 1;
          if (erase_lock_status_bit_index = 0) then 
            --status(0) is write in progress flag bit
            --note: Hualin's firmware only checks this on bit 0 of the next cycle. Not sure if necessary
            if (spi_miso = '0' or in_simulation) then
              erase_lock_state <= S_ERASE_LOCK_IDLE;
              erase_lock_done <= '1';
            end if;
            --erase_lock_in_progress_bit <= spi_miso;
          end if;
        end if;
   end case;  
 end if;  -- Clk
end process process_erase_lock;

-------------------------------  WRITE LOCK FSM  --------------------------------------------------
process_write_lock : process (CLK)
  begin
  if rising_edge(CLK) then
  case write_lock_state is 
   when S_WRITE_LOCK_IDLE =>
        --when START_WRITE received, initiate write process
        if (START_ADDRESS_VALID = '1') then 
          write_lock_address <= START_ADDRESS; 
          write_lock_address_volatile <= START_ADDRESS(23 downto 0) & x"00";
        end if; --4-byte addressing for nonvolatile, 3 for volatile
        write_lock_spi_cs_bar <= '1';
        if (START_LOCK(0) = '1') then
          write_lock_type <= START_LOCK;
          write_lock_done <= '0';
          write_lock_state <= S_WRITE_LOCK_ASSERT_CS_WRITE_ENABLE;
        else
          write_lock_done <= '1';
        end if;
                       
   when S_WRITE_LOCK_ASSERT_CS_WRITE_ENABLE =>
        --assert CS and prep write enable commmand
        write_lock_cmdcounter <= "000111"; --8 bits of command
        write_lock_cmdreg <=  CmdWE & X"00000000";
        write_lock_spi_cs_bar <= '0';
        write_lock_state <= S_WRITE_LOCK_SHIFT_WRITE_ENABLE;
                  
   when S_WRITE_LOCK_SHIFT_WRITE_ENABLE =>
         --shift write enable
         if (write_lock_cmdcounter /= 0) then 
           write_lock_cmdcounter <= write_lock_cmdcounter - 1;  
           write_lock_cmdreg <= write_lock_cmdreg(38 downto 0) & '0';
         else 
           write_lock_spi_cs_bar <= '1';
           write_lock_state <= S_WRITE_LOCK_ASSERT_CS_WRITE_LOCK;        
         end if;
                   
   when S_WRITE_LOCK_ASSERT_CS_WRITE_LOCK =>
        --assert CS and prepare for write nonvolatile lock bits
        write_lock_spi_cs_bar <= '0';   
        if (write_lock_type(2 downto 1) = "00") then --nonvolatile
          write_lock_cmdreg <= CmdWriteNonvLock & write_lock_address; 
          write_lock_cmdcounter <= "100111"; --40 bits: 8 command + 32 for address
        elsif (write_lock_type(2 downto 1) = "01") then
          write_lock_cmdreg <= CmdWriteVolaLock & write_lock_address_volatile(31 downto 8) & x"01"; 
          write_lock_cmdcounter <= "100111"; --40 bits: 8 command + 24 for address + 8 for register
        else
          write_lock_cmdreg <= CmdWriteVolaLock & write_lock_address_volatile(31 downto 8) & x"00"; 
          write_lock_cmdcounter <= "100111"; --40 bits: 8 command + 24 for address + 8 for register
        end if;
        write_lock_state <= S_WRITE_LOCK_SHIFT_WRITE_LOCK;
                      
   when S_WRITE_LOCK_SHIFT_WRITE_LOCK =>     
        --shift write nonvolatile lock bits command
        if (write_lock_cmdcounter /= 0) then 
          write_lock_cmdcounter <= write_lock_cmdcounter - 1;
          write_lock_cmdreg <= write_lock_cmdreg(38 downto 0) & '0';
        else
          write_lock_spi_cs_bar <= '1';
          write_lock_state <= S_WRITE_LOCK_ASSERT_CS_READ_STATUS;
        end if;

   when S_WRITE_LOCK_ASSERT_CS_READ_STATUS =>
        -- assert CS and prep read status command
        -- this part is strange, if only do read status once, will get 11111111 always from miso
        write_lock_spi_cs_bar <= '0';
        write_lock_cmdcounter <= "011111"; --16 bits: 8 command + 8 to skip the first cycle
        write_lock_cmdreg <=  CmdStatus & X"00000000";
        write_lock_state <= S_WRITE_LOCK_SHIFT_READ_STATUS;
        
   when S_WRITE_LOCK_SHIFT_READ_STATUS =>
        --shift read status command and read back status register
        if (write_lock_cmdcounter /= 0) then 
          write_lock_cmdcounter <= write_lock_cmdcounter - 1;
          write_lock_cmdreg <= write_lock_cmdreg(38 downto 0) & '0';
        else
          write_lock_spi_cs_bar <= '1';
          if (write_lock_type(2 downto 1) = "00") then
            write_lock_state <= S_WRITE_LOCK_ASSERT_CS_READ_STATUS_2;
          else
            write_lock_done <= '1';
             write_lock_state <= S_WRITE_LOCK_IDLE;
          end if;
        end if; --write_lock_cmdcounter = 

   when S_WRITE_LOCK_ASSERT_CS_READ_STATUS_2 =>
        -- assert CS and prep read status command
        write_lock_spi_cs_bar <= '0';
        write_lock_cmdcounter <= "011111"; --16 bits: 8 command + 8 to skip the first cycle
        write_lock_status_bit_index <= x"00";
        write_lock_cmdreg <=  CmdStatus & X"00000000";
        write_lock_state <= S_WRITE_LOCK_SHIFT_READ_STATUS_2;

   when S_WRITE_LOCK_SHIFT_READ_STATUS_2 =>
        --shift read status command and read back status register
        if (write_lock_cmdcounter /= 0) then 
          write_lock_cmdcounter <= write_lock_cmdcounter - 1;
          write_lock_cmdreg <= write_lock_cmdreg(38 downto 0) & '0';
        else
          --once command is shifted and first read cycle skipped, check bit 0 on each cycle to see if done
          write_lock_status_bit_index <= write_lock_status_bit_index + 1;
          if (write_lock_status_bit_index = 0) then 
            --status(0) is write_lock in progress flag bit
            --note: Hualin's firmware only checks this on bit 0 of the next cycle. Not sure if necessary
            if (spi_miso = '0' or in_simulation) then
              write_lock_done <= '1';
              write_lock_state <= S_WRITE_LOCK_IDLE;
            end if; --spi_miso = '0' or in_simulation
          end if; --write_lock_status_bit_index = 0
        end if; --write_lock_cmdcounter = 0

   end case;  
 end if;  -- Clk
end process process_write_lock;

-------------------------------  READ LOCK FSM  --------------------------------------------------
process_read_lock : process (CLK)
  begin
  if rising_edge(CLK) then
  case read_lock_state is 
  when S_READ_LOCK_IDLE =>
       --when START_READ_LOCK received, initiate write process
       read_lock_spi_cs_bar <= '1';
       read_lock_data_valid <= '0';
       if (START_ADDRESS_VALID = '1') then 
         read_lock_address <= START_ADDRESS; 
         read_lock_address_volatile <= START_ADDRESS(23 downto 0) & x"00";
       end if; --4-byte addressing for nonvolatile, 3 for volatile
       if (START_READ_LOCK(0) = '1') then
         read_lock_type <= START_READ_LOCK;
         read_lock_done <= '0';
         read_lock_state <= S_READ_LOCK_ASSERT_CS_READ;
       else
         read_lock_done <= '1';
         read_lock_state <= S_READ_LOCK_IDLE;
       end if;

  when S_READ_LOCK_ASSERT_CS_READ =>
       -- assert CS and prep read id command
       read_lock_spi_cs_bar <= '0';
       read_lock_cmdcounter <= "000111"; --8 bits for command
       if (read_lock_type(1) = '0') then
         read_lock_cmdreg <=  CmdReadNonvLock & read_lock_address;
         read_lock_cmdcounter <= "100111"; --40 bits: 8 command + 32 for address
       else
         read_lock_cmdreg <=  CmdReadVolaLock & read_lock_address_volatile;
         read_lock_cmdcounter <= "100110"; --39 bits: 8 command + 24 for address + 7 until last bit of volatile register
       end if;
       read_lock_data_counter <= "10"; 
       read_lock_state <= S_READ_LOCK_SHIFT_READ;
       
  when S_READ_LOCK_SHIFT_READ =>
       --shift read id command and read back 
       if (read_lock_cmdcounter /= 0) then 
         read_lock_cmdcounter <= read_lock_cmdcounter - 1;
         read_lock_cmdreg <= read_lock_cmdreg(38 downto 0) & '0';
         read_lock_data_valid <= '0';
       else
         read_lock_data_counter <= read_lock_data_counter - 1;
         read_lock_data <= read_lock_data(15 downto 1) & spi_miso;
         if (read_lock_data_counter = "00") then
           read_lock_data_valid <= '1';
           read_lock_state <= S_READ_LOCK_IDLE;
           --wait one cycle for read_lock_done to allow read_lock_data to be read
         else
           read_lock_data_valid <= '0';
           read_lock_state <= S_READ_LOCK_SHIFT_READ;
         end if;
       end if; --read_lock_cmdcounter = 0

  end case;  
  end if;  -- Clk
end process process_read_lock;

-------------------------------  WRITE CONFIG FSM  --------------------------------------------------
process_write_config : process (CLK)
  begin
  if rising_edge(CLK) then
  case write_config_state is 
   when S_WRITE_CONFIG_IDLE =>
        --when START_WRITE_CONFIG received, initiate write process
        write_config_spi_cs_bar <= '1';
        if (START_WRITE_REGISTER(3) = '1') then
          write_config_done <= '0';
          write_register_type <= START_WRITE_REGISTER;
          write_config_state <= S_WRITE_CONFIG_ASSERT_CS_WRITE_ENABLE;
        else
          write_config_done <= '1';
        end if;
                       
   when S_WRITE_CONFIG_ASSERT_CS_WRITE_ENABLE =>
        --assert CS and prep write enable commmand
        write_config_cmdcounter <= "000111"; --8 bits of command
        write_config_cmdreg <=  CmdWE & X"00000000";
        write_config_spi_cs_bar <= '0';
        write_config_state <= S_WRITE_CONFIG_SHIFT_WRITE_ENABLE;
                  
   when S_WRITE_CONFIG_SHIFT_WRITE_ENABLE =>
         --shift write enable
         if (write_config_cmdcounter /= 0) then 
           write_config_cmdcounter <= write_config_cmdcounter - 1;  
           write_config_cmdreg <= write_config_cmdreg(38 downto 0) & '0';
         else 
           write_config_spi_cs_bar <= '1';
           write_config_state <= S_WRITE_CONFIG_ASSERT_CS_WRITE_CONFIG;        
         end if;
                   
   when S_WRITE_CONFIG_ASSERT_CS_WRITE_CONFIG =>
        --assert CS and prepare for write nonvolatile config bits
        write_config_spi_cs_bar <= '0';   
        if (write_register_type = x"9") then --status
          write_config_cmdcounter <= "001111"; --16 bits: 8 command + 8 register
          write_config_cmdreg <= CmdWriteStatus & REGISTER_CONTENTS(7 downto 0) & x"000000"; 
        elsif (write_register_type = x"B") then --nonvolatile
          write_config_cmdcounter <= "010111"; --24 bits: 8 command + 16 register
          --endianness has LSbyte first
          write_config_cmdreg <= CmdWriteNonvConfig & REGISTER_CONTENTS(7 downto 0) & REGISTER_CONTENTS(15 downto 8) & x"0000"; 
        elsif (write_register_type = x"D") then --volatile
          write_config_cmdcounter <= "001111"; --16 bits: 8 command + 8 register
          write_config_cmdreg <= CmdWriteVolaConfig & REGISTER_CONTENTS(7 downto 0) & x"000000"; 
        else --'E' enhanved volatile
          write_config_cmdcounter <= "001111"; --16 bits: 8 command + 8 register
          write_config_cmdreg <= CmdWriteExteConfig & REGISTER_CONTENTS(7 downto 0) & x"000000"; 
        end if;
        write_config_state <= S_WRITE_CONFIG_SHIFT_WRITE_CONFIG;
                      
   when S_WRITE_CONFIG_SHIFT_WRITE_CONFIG =>     
        --shift write nonvolatile config bits command
        if (write_config_cmdcounter /= 0) then 
          write_config_cmdcounter <= write_config_cmdcounter - 1;
          write_config_cmdreg <= write_config_cmdreg(38 downto 0) & '0';
        else
          write_config_spi_cs_bar <= '1';
          write_config_state <= S_WRITE_CONFIG_ASSERT_CS_READ_STATUS;
        end if;

   when S_WRITE_CONFIG_ASSERT_CS_READ_STATUS =>
        -- assert CS and prep read status command
        -- this part is strange, if only do read status once, will get 11111111 always from miso
        write_config_spi_cs_bar <= '0';
        write_config_cmdcounter <= "011111"; --16 bits: 8 command + 8 to skip the first cycle
        write_config_cmdreg <=  CmdStatus & X"00000000";
        write_config_state <= S_WRITE_CONFIG_SHIFT_READ_STATUS;
        
   when S_WRITE_CONFIG_SHIFT_READ_STATUS =>
        --shift read status command and read back status register
        if (write_config_cmdcounter /= 0) then 
          write_config_cmdcounter <= write_config_cmdcounter - 1;
          write_config_cmdreg <= write_config_cmdreg(38 downto 0) & '0';
        else
          write_config_spi_cs_bar <= '1';
          write_config_state <= S_WRITE_CONFIG_ASSERT_CS_READ_STATUS_2;
        end if; --write_config_cmdcounter = 

   when S_WRITE_CONFIG_ASSERT_CS_READ_STATUS_2 =>
        -- assert CS and prep read status command
        write_config_spi_cs_bar <= '0';
        write_config_cmdcounter <= "011111"; --16 bits: 8 command + 8 to skip the first cycle
        write_config_status_bit_index <= x"00";
        write_config_cmdreg <=  CmdStatus & X"00000000";
        write_config_state <= S_WRITE_CONFIG_SHIFT_READ_STATUS_2;

   when S_WRITE_CONFIG_SHIFT_READ_STATUS_2 =>
        --shift read status command and read back status register
        if (write_config_cmdcounter /= 0) then 
          write_config_cmdcounter <= write_config_cmdcounter - 1;
          write_config_cmdreg <= write_config_cmdreg(38 downto 0) & '0';
        else
          --once command is shifted and first read cycle skipped, check bit 0 on each cycle to see if done
          write_config_status_bit_index <= write_config_status_bit_index + 1;
          if (write_config_status_bit_index = 0) then 
            --status(0) is write_config in progress flag bit
            --note: Hualin's firmware only checks this on bit 0 of the next cycle. Not sure if necessary
            if (spi_miso = '0' or in_simulation) then
              write_config_done <= '1';
              write_config_state <= S_WRITE_CONFIG_IDLE;
            end if; --spi_miso = '0' or in_simulation
          end if; --write_config_status_bit_index = 0
        end if; --write_config_cmdcounter = 0

   end case;  
 end if;  -- Clk
end process process_write_config;

-------------------------------  READ REGISTER FSM  --------------------------------------------------
process_read_register : process (CLK)
  begin
  if rising_edge(CLK) then
  case read_register_state is 
  when S_READ_REGISTER_IDLE =>
       --when START_READ_REGISTER received, initiate write process
       read_register_spi_cs_bar <= '1';
       register_we <= '0';
       if (START_READ_REGISTER /= x"0") then
         read_register_done <= '0';
         read_register_state <= S_READ_REGISTER_ASSERT_CS_READ;
         read_register_type <= START_READ_REGISTER;
       else
         read_register_done <= '1';
         read_register_state <= S_READ_REGISTER_IDLE;
       end if;

  when S_READ_REGISTER_ASSERT_CS_READ =>
       -- assert CS and prep read register command
       read_register_spi_cs_bar <= '0';
       read_register_bit_index <= x"00";
       --read_register_cmdcounter <= "010111"; --24 bits: 8 command + 16 to skip the first cycle (or 2)
       read_register_cmdcounter <= "000111"; --8 bits for command; don't skip first cycle since Nonvolatile register only outputs once
       --MO I thought we would end on max_index=8/10, but that results in an off-by-one error so 9/11 it is
       if (read_register_type = x"1") then
         read_register_cmdreg <=  CmdStatus & x"00000000";
         read_register_max_index <= x"09";
       elsif (read_register_type = x"2") then
         read_register_cmdreg <=  CmdFLAGStatus & x"00000000";
         read_register_max_index <= x"09";
       elsif (read_register_type = x"3") then
         read_register_cmdreg <=  CmdReadNonvConf & x"00000000";
         read_register_max_index <= x"09";
       elsif (read_register_type = x"4") then
         read_register_cmdreg <=  CmdReadNonvConf & x"00000000";
         read_register_max_index <= x"11"; --MSBs for nonvolatile register
       elsif (read_register_type = x"5") then
         read_register_cmdreg <=  CmdReadVolaConf & x"00000000";
         read_register_max_index <= x"09";
       else
         read_register_cmdreg <=  CmdReadExteConf & x"00000000";
         read_register_max_index <= x"09";
       end if;
       read_register_state <= S_READ_REGISTER_SHIFT_READ;
       
  when S_READ_REGISTER_SHIFT_READ =>
       --shift read register command and read back 
       if (read_register_cmdcounter /= 0) then 
         read_register_cmdcounter <= read_register_cmdcounter - 1;
         read_register_cmdreg <= read_register_cmdreg(38 downto 0) & '0';
       else
         read_register_bit_index <= read_register_bit_index + 1;
         register_inner <= register_inner(6 downto 0)  & spi_miso; -- & register_inner(7 downto 1);
         if (read_register_bit_index = read_register_max_index) then 
           read_register_done <= '1';
           register_we <= '1';
           read_register_state <= S_READ_REGISTER_IDLE;
         end if;
       end if; --read_register_cmdcounter = 0

  end case;  
  end if;  -- Clk
end process process_read_register;

-------------------------------  READ ID FSM  --------------------------------------------------
process_read_id : process (CLK)
  begin
  if rising_edge(CLK) then
  case read_id_state is 
  when S_READ_ID_IDLE =>
       --when START_READ_ID received, initiate write process
       read_id_spi_cs_bar <= '1';
       read_id_data_valid <= '0';
       if (START_READ_ID = '1') then
         read_id_done <= '0';
         read_id_state <= S_READ_ID_ASSERT_CS_READ;
       else
         read_id_done <= '1';
         read_id_state <= S_READ_ID_IDLE;
       end if;

  when S_READ_ID_ASSERT_CS_READ =>
       -- assert CS and prep read id command
       read_id_spi_cs_bar <= '0';
       read_id_cmdcounter <= "000111"; --8 bits for command
       read_id_cmdreg <=  CmdRDID & x"00000000";
       read_id_data_counter <= x"a1"; --ID is 20 bytes
       read_id_state <= S_READ_ID_SHIFT_READ;
       
  when S_READ_ID_SHIFT_READ =>
       --shift read id command and read back 
       if (read_id_cmdcounter /= 0) then 
         read_id_cmdcounter <= read_id_cmdcounter - 1;
         read_id_cmdreg <= read_id_cmdreg(38 downto 0) & '0';
       else
         read_id_data_counter <= read_id_data_counter - 1;
         read_id_data <= read_id_data(14 downto 0) & spi_miso;
         if (read_id_data_counter(3 downto 0) = x"0" and read_id_data_counter(7 downto 4) /= x"a") then
           read_id_data_valid <= '1';
         else
           read_id_data_valid <= '0';
         end if;
         if (read_id_data_counter = x"00") then
           --wait one cycle for read_id_done to allow last read_id_data to be read
           read_id_state <= S_READ_ID_IDLE;
         else
           read_id_state <= S_READ_ID_SHIFT_READ;
         end if;
       end if; --read_id_cmdcounter = 0

  end case;  
  end if;  -- Clk
end process process_read_id;


-------------------------------  CLEAR STATUS FSM --------------------------------------------------
process_clear_status : process (CLK)
  begin
  if rising_edge(CLK) then
  case clear_status_state is 
  when S_CLEAR_STATUS_IDLE =>
       --when START_CLEAR_STATUS received, initiate write process
       clear_status_spi_cs_bar <= '1';
       if (START_CLEAR_STATUS = '1') then
         clear_status_done <= '0';
         clear_status_state <= S_CLEAR_STATUS_ASSERT_CS;
       else
         clear_status_done <= '1';
         clear_status_state <= S_CLEAR_STATUS_IDLE;
       end if;

  when S_CLEAR_STATUS_ASSERT_CS =>
       -- assert CS and prep clear status command
       clear_status_spi_cs_bar <= '0';
       clear_status_cmdcounter <= "000111"; --8 bits for command
       clear_status_cmdreg <=  CmdClearFlagStatus & x"00000000";
       clear_status_state <= S_CLEAR_STATUS_SHIFT;
       
  when S_CLEAR_STATUS_SHIFT =>
       --shift read id command and read back 
       if (clear_status_cmdcounter /= 0) then 
         clear_status_cmdcounter <= clear_status_cmdcounter - 1;
         clear_status_cmdreg <= clear_status_cmdreg(38 downto 0) & '0';
         clear_status_spi_cs_bar <= '0';
       else
         clear_status_done <= '1';
         clear_status_state <= S_CLEAR_STATUS_IDLE;
         clear_status_spi_cs_bar <= '1';
       end if; --clear_status_cmdcounter = 0

  end case;  
  end if;  -- Clk
end process process_clear_status;

-------------------------------  CUSTOM COMMAND FSM  --------------------------------------------------

process_custom : process (CLK)
  begin
  if rising_edge(Clk) then
  case custom_state is 
  when S_CUSTOM_IDLE =>
        custom_spi_cs_bar <= '1';
        custom_fifo_read_enable <= '0';
        custom_data_valid <= '0';
        --initalize custom process when START_CUSTOM received
        if (START_CUSTOM(0) = '1' and custom_enable = '1') then
          custom_nbits_write <= unsigned(START_CUSTOM(11 downto 1));
          custom_nwords_read <= unsigned(CUSTOM_WORDS_TO_READ);
          custom_fifo_idx <= "11";
          custom_done <= '0';
          custom_state <= S_CUSTOM_ASSERT_CS;
        else
          custom_done <= '1';
        end if;
                   
   when S_CUSTOM_ASSERT_CS =>
        --assert CS and prepare custom command
        custom_spi_cs_bar <= '0';
        custom_mosi <= write_fifo_output(to_integer(custom_fifo_idx));
        custom_fifo_idx <= custom_fifo_idx - 1;
        custom_state <= S_CUSTOM_SHIFT;
        custom_first_read_cycle <= '1';
        custom_data_counter <= x"0";
                                                 
   when S_CUSTOM_SHIFT =>
        -- shift custom command
        if (custom_nbits_write /= 0) then 
          custom_mosi <= write_fifo_output(to_integer(custom_fifo_idx));
          custom_nbits_write <= custom_nbits_write - 1;
          custom_fifo_idx <= custom_fifo_idx - 1;
          if (custom_fifo_idx = 1) then
            custom_fifo_read_enable <= '1';
          else
            custom_fifo_read_enable <= '0';
          end if;
          if (custom_nbits_write = 1 and custom_nwords_read = 0) then
            custom_state <= S_CUSTOM_FLUSH_FIFO;
            custom_spi_cs_bar <= '1';
            custom_nbits_write <= "00000000011";
          end if;
        else --finished shifting write, now read
          custom_fifo_read_enable <= '0';
          custom_data <= custom_data(14 downto 0) & spi_miso;
          custom_data_counter <= custom_data_counter + 1;
          if (custom_data_counter = x"0") then
            if (custom_first_read_cycle = '1') then
              custom_first_read_cycle <= '0';
              custom_data_valid <= '0';
            else
              custom_data_valid <= '1';
              custom_nwords_read <= custom_nwords_read - 1;
            end if;
          else
            custom_data_valid <= '0';
          end if;
          if (custom_nwords_read = 0) then
            custom_state <= S_CUSTOM_FLUSH_FIFO;
            custom_spi_cs_bar <= '1';
            custom_nbits_write <= "00000000110";
          end if;
        end if; --reading
                          
   when S_CUSTOM_FLUSH_FIFO =>
        --remove any remaining words in fifo
        if (custom_nbits_write = 0) then
          custom_fifo_read_enable <= '0';
          custom_done <= '1';
          custom_state <= S_CUSTOM_IDLE;
        else
          custom_data_valid <= '0';
          custom_fifo_read_enable <= '1';
          custom_nbits_write <= custom_nbits_write - 1;
        end if;

  end case;
    
  end if;  -- CLK
end process process_custom;


--------------********* misc **************---------------------
--fifo_unconned(15 downto 0) <= data_to_fifo;
---- to top design. Some may require syncronizers when used   
--fifofull    <= fifo_full;
--fifoempty   <= fifo_empty;        -- May require synconizer when used
--fifoafull   <= fifo_almostfull;   -- May require synconizer when used
--fifowrerr   <= wrerr;
--fiforderr   <= rderr;             -- May require synconizer when used

--DIAGOUT(3 downto 0) <= do_in;
--DIAGOUT(4) <= di_out(1);
--DIAGOUT(5) <= spi_cs_bar;
--DIAGOUT(6) <= START_READ;
--DIAGOUT(7) <= read_done;
--DIAGOUT(8) <= START_ERASE;
--DIAGOUT(9) <= erase_done;
--DIAGOUT(10) <= START_WRITE;
--DIAGOUT(11) <= write_done;
--DIAGOUT(12) <= WRITE_FIFO_WRITE_ENABLE;
--DIAGOUT(13) <= read_data_valid;
--DIAGOUT(14) <= START_ADDRESS_VALID;
--DIAGOUT(17 downto 15) <= read_data(2 downto 0);
DIAGOUT(7 downto 0) <= WRITE_FIFO_INPUT(7 downto 0);
DIAGOUT(8) <= read_data_valid;
DIAGOUT(9) <= WRITE_FIFO_WRITE_ENABLE;
DIAGOUT(11 downto 10) <= read_data(1 downto 0);
DIAGOUT(15 downto 12) <= do_in;
DIAGOUT(16) <= spi_cs_bar;
DIAGOUT(17) <= START_ADDRESS_VALID;

end behavioral;

