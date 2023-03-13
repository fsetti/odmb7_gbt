------------------------------
-- ODMB_CTRL: controls triggers, calibration, and the data path
------------------------------

library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_misc.all;

library unisim;
use unisim.vcomponents.all;
use work.ucsb_types.all;
-- use work.odmb7_components.all;

entity ODMB_CTRL is
  generic (
    NCFEB       : integer range 1 to 7 := 7;  -- Number of DCFEBS, 7 for ME1/1, 5
    CAFIFO_SIZE : integer range 1 to 128 := 32  -- Number FIFO words in CAFIFO
  );
  PORT (
    --------------------
    -- Clock
    --------------------
    DDUCLK       : in std_logic;
    CMSCLK       : in std_logic;

    CCB_CMD      : in  std_logic_vector (5 downto 0);  -- ccbcmnd(5 downto 0) - from J3
    CCB_CMD_S    : in  std_logic;       -- ccbcmnd(6) - from J3
    CCB_DATA     : in  std_logic_vector (7 downto 0);  -- ccbdata(7 downto 0) - from J3
    CCB_DATA_S   : in  std_logic;       -- ccbdata(8) - from J3
    CCB_BX0_B    : in  std_logic;       -- bx0 - from J3
    CCB_BXRST_B  : in  std_logic;       -- bxrst - from J3
    CCB_L1ARST_B : in  std_logic;       -- l1rst - from J3
    CCB_CLKEN    : in  std_logic;       -- clken - from J3
    --------------------
    -- ODMB VME <-> CALIBTRIG
    --------------------
    TEST_CCBINJ   : in std_logic;
    TEST_CCBPLS   : in std_logic;
    TEST_CCBPED   : in std_logic;

    --------------------
    -- Delay registers (from VMECONFREGS)
    --------------------
    LCT_L1A_DLY   : in std_logic_vector(5 downto 0);
    INJ_DLY       : in std_logic_vector(4 downto 0);
    EXT_DLY       : in std_logic_vector(4 downto 0);
    CALLCT_DLY    : in std_logic_vector(3 downto 0);
    OTMB_PUSH_DLY : in integer range 0 to 63;
    ALCT_PUSH_DLY : in integer range 0 to 63;
    PUSH_DLY      : in integer range 0 to 63;

    --------------------
    -- Configuration
    --------------------
    CAL_MODE      : in std_logic;
    PEDESTAL      : in std_logic;
    PEDESTAL_OTMB   : in  std_logic;

    --------------------
    -- TRGCNTRL
    --------------------
    RAW_L1A       : in std_logic;
    RAWLCT        : in std_logic_vector (NCFEB downto 0);
    
    --------------------
    -- DAV 
    --------------------
    OTMB_DAV : in std_logic;            
    ALCT_DAV : in std_logic;            

    --------------------
    -- To/From DCFEBs (FF-EMU-MOD)
    --------------------
    DCFEB_INJPULSE  : out std_logic;
    DCFEB_EXTPULSE  : out std_logic;
    DCFEB_L1A       : out std_logic;
    DCFEB_L1A_MATCH : out std_logic_vector(NCFEB downto 1);

    ALCT_DAV_SYNC_OUT : out std_logic;
    OTMB_DAV_SYNC_OUT : out std_logic;

    --------------------
    -- Other
    --------------------
    DIAGOUT     : out std_logic_vector (17 downto 0); -- for debugging
    KILL        : in std_logic_vector(NCFEB+2 downto 1);
    LCT_ERR     : out std_logic;            -- To an LED in the original design

    BX_DLY      : in integer range 0 to 4095;
    L1ACNT_RST  : in std_logic;
    BXCNT_RST   : in std_logic;
    RST         : in std_logic;

    EOF_DATA    : in std_logic_vector(NCFEB+2 downto 1);

    CAFIFO_PREV_NEXT_L1A_MATCH : out std_logic_vector(15 downto 0);
    CAFIFO_PREV_NEXT_L1A       : out std_logic_vector(15 downto 0);
    CONTROL_DEBUG              : out std_logic_vector(15 downto 0);
    CAFIFO_DEBUG               : out std_logic_vector(15 downto 0);
    CAFIFO_WR_ADDR             : out std_logic_vector(7 downto 0);
    CAFIFO_RD_ADDR             : out std_logic_vector(7 downto 0);

    -- From CAFIFO to Data FIFOs
    CAFIFO_L1A           : out std_logic;
    CAFIFO_L1A_MATCH_IN  : out std_logic_vector(NCFEB+2 downto 1);  -- From TRGCNTRL to CAFIFO to generate Data  
    CAFIFO_L1A_MATCH_OUT : out std_logic_vector(NCFEB+2 downto 1);  -- From CAFIFO to CONTROL  
    CAFIFO_L1A_CNT       : out std_logic_vector(23 downto 0);
    CAFIFO_L1A_DAV       : out std_logic_vector(NCFEB+2 downto 1);
    CAFIFO_BX_CNT        : out std_logic_vector(11 downto 0);

    -- From GigaLinks
    DDU_DATA       : out std_logic_vector(15 downto 0);
    DDU_DATA_VALID : out std_logic;

    -- For headers/trailers
    --DAQMBID : in std_logic_vector(11 downto 0);  -- From CRATEID in SETFEBDLY, and GA
    GA : in std_logic_vector(4 downto 0);
    CRATEID : in std_logic_vector(7 downto 0);  -- From CRATEID in SETFEBDLY, and GA
    AUTOKILLED_DCFEBS  : in std_logic_vector(NCFEB downto 1);
      
    -- From/To Data FIFOs
    FIFO_RE_B      : out std_logic_vector(NCFEB+2 downto 1);
    FIFO_OE_B      : out std_logic_vector(NCFEB+2 downto 1);
    FIFO_DOUT      : in std_logic_vector(17 downto 0);
    FIFO_EMPTY     : in std_logic_vector(NCFEB+2 downto 1);  -- emptyf*(7 DOWNTO 1) - from FIFOs
    FIFO_HALF_FULL : in std_logic_vector(NCFEB+2 downto 1)  -- 
    );
end ODMB_CTRL;

architecture Behavioral of ODMB_CTRL is

  component CALIBTRG is
    port (
      CMSCLK      : in  std_logic;
      CLK80       : in  std_logic;
      RST         : in  std_logic;
      PLSINJEN    : in  std_logic;
      CCBPLS      : in  std_logic;
      CCBINJ      : in  std_logic;
      FPLS        : in  std_logic;
      FINJ        : in  std_logic;
      FPED        : in  std_logic;
      PRELCT      : in  std_logic;
      PREGTRG     : in  std_logic;
      INJ_DLY     : in  std_logic_vector(4 downto 0);
      EXT_DLY     : in  std_logic_vector(4 downto 0);
      CALLCT_DLY  : in  std_logic_vector(3 downto 0);
      LCT_L1A_DLY : in  std_logic_vector(5 downto 0);
      RNDMPLS     : in  std_logic;
      RNDMGTRG    : in  std_logic;
      PEDESTAL    : out std_logic;
      CAL_GTRG    : out std_logic;
      CALLCT      : out std_logic;
      INJBACK     : out std_logic;
      PLSBACK     : out std_logic;
      LCTRQST     : out std_logic;
      INJPLS      : out std_logic
      );
  end component;

  -- components used in odmb_ctrl
  component TRGCNTRL is
    generic (
      NCFEB : integer range 1 to 7 := 5  -- Number of DCFEBS, 7 in the final design
      );  
    port (
      CLK           : in std_logic;
      RAW_L1A       : in std_logic;
      RAW_LCT       : in std_logic_vector(NCFEB downto 0);
      CAL_LCT       : in std_logic;
      CAL_L1A       : in std_logic;
      LCT_L1A_DLY   : in std_logic_vector(5 downto 0);
      OTMB_PUSH_DLY : in integer range 0 to 63;
      ALCT_PUSH_DLY : in integer range 0 to 63;
      PUSH_DLY      : in integer range 0 to 63;
      ALCT_DAV      : in std_logic;
      OTMB_DAV      : in std_logic;

      CAL_MODE      : in std_logic;
      KILL          : in std_logic_vector(NCFEB+2 downto 1);
      PEDESTAL      : in std_logic;
      PEDESTAL_OTMB : in std_logic;

      ALCT_DAV_SYNC_OUT : out std_logic;
      OTMB_DAV_SYNC_OUT : out std_logic;

      DCFEB_L1A       : out std_logic;
      DCFEB_L1A_MATCH : out std_logic_vector(NCFEB downto 1);
      FIFO_PUSH       : out std_logic;
      FIFO_L1A_MATCH  : out std_logic_vector(NCFEB+2 downto 0);
      LCT_ERR         : out std_logic;
      
      DIAGOUT         : out std_logic_vector(26 downto 0)
      );
  end component;

  component cafifo is
    generic (
      NCFEB        : integer range 1 to 7   := 7;  -- Number of DCFEBS, 7 in the final design
      CAFIFO_SIZE : integer range 1 to 128 := 32  -- Number of CAFIFO words
      );  
    port(

      --CSP_FREE_AGENT_PORT_LA_CTRL : inout std_logic_vector(35 downto 0);
      clk                         : in    std_logic;
      dduclk                      : in    std_logic;
      l1acnt_rst                  : in    std_logic;
      bxcnt_rst                   : in    std_logic;

      BC0     : in std_logic;
      CCB_BX0 : in std_logic;
      BXRST   : in std_logic;
      BX_DLY  : in integer range 0 to 4095;
      PUSH_DLY  : in integer range 0 to 63;

      l1a          : in std_logic;
      l1a_match_in : in std_logic_vector(NCFEB+2 downto 1);

      pop          : in std_logic;
      eof_data     : in std_logic_vector(NCFEB+2 downto 1);

      cafifo_l1a_match : out std_logic_vector(NCFEB+2 downto 1);
      cafifo_l1a_cnt   : out std_logic_vector(23 downto 0);
      cafifo_l1a_dav   : out std_logic_vector(NCFEB+2 downto 1);
      cafifo_bx_cnt    : out std_logic_vector(11 downto 0);
      cafifo_lost_pckt : out std_logic_vector(NCFEB+2 downto 1);
      cafifo_lone      : out std_logic;

      cafifo_prev_next_l1a_match : out std_logic_vector(15 downto 0);
      cafifo_prev_next_l1a       : out std_logic_vector(15 downto 0);
      control_debug              : in  std_logic_vector(143 downto 0);
      cafifo_debug               : out std_logic_vector(15 downto 0);
      cafifo_wr_addr             : out std_logic_vector(7 downto 0);
      cafifo_rd_addr             : out std_logic_vector(7 downto 0)
      );

  end component;

  component CONTROL_FSM is
    generic (
      NCFEB : integer range 1 to 7 := 5  -- Number of DCFEBS, 7 in the final design
      );  
    port (
      -- Chip Scope Pro Logic Analyzer control
      --CSP_CONTROL_FSM_PORT_LA_CTRL : inout std_logic_vector(35 downto 0);
      RST                          : in    std_logic;
      CLKCMS                       : in    std_logic;
      CLK                          : in    std_logic;
      STATUS                       : in    std_logic_vector(47 downto 0);

      -- From DMB_VME
      RDFFNXT : in std_logic;
      KILL    : in std_logic_vector(NCFEB+2 downto 1);

      -- to GigaBit Link
      DOUT : out std_logic_vector(15 downto 0);
      DAV  : out std_logic;

      -- to FIFOs
      OEFIFO_B  : out std_logic_vector(NCFEB+2 downto 1);
      RENFIFO_B : out std_logic_vector(NCFEB+2 downto 1);

      -- from FIFOs
      FIFO_HALF_FULL : in std_logic_vector(NCFEB+2 downto 1);
      FFOR_B         : in std_logic_vector(NCFEB+2 downto 1);
      DATAIN         : in std_logic_vector(15 downto 0);
      DATAIN_LAST    : in std_logic;

      -- From LOADFIFO
      JOEF : in std_logic_vector(NCFEB+2 downto 1);

      -- For headers/trailers
      DAQMBID : in std_logic_vector(11 downto 0);  -- From CRATEID in SETFEBDLY, and GA
      AUTOKILLED_DCFEBS  : in std_logic_vector(NCFEB downto 1);

      -- FROM SW1
      GIGAEN : in std_logic;

      -- TO CAFIFO
      FIFO_POP : out std_logic;

      -- TO PCFIFO
      EOF : out std_logic;

      -- DEBUG
      control_debug : out std_logic_vector(143 downto 0);

      -- FROM CAFIFO
      cafifo_l1a_dav   : in std_logic_vector(NCFEB+2 downto 1);
      cafifo_l1a_match : in std_logic_vector(NCFEB+2 downto 1);
      cafifo_l1a_cnt   : in std_logic_vector(23 downto 0);
      cafifo_bx_cnt    : in std_logic_vector(11 downto 0);
      cafifo_lost_pckt : in std_logic_vector(NCFEB+2 downto 1);
      cafifo_lone      : in std_logic
      );
  end component;

  component CCBCODE is
    port (
      CCB_CMD      : in  std_logic_vector(5 downto 0);
      CCB_CMD_S    : in  std_logic;
      CCB_DATA     : in  std_logic_vector(7 downto 0);
      CCB_DATA_S   : in  std_logic;
      CMSCLK       : in  std_logic;
      CCB_BXRST_B  : in  std_logic;
      CCB_BX0_B    : in  std_logic;
      CCB_L1ARST_B : in  std_logic;
      CCB_CLKEN    : in  std_logic;
      BX0          : out std_logic;
      BXRST        : out std_logic;
      L1ARST       : out std_logic;
      CLKEN        : out std_logic;
      BC0          : out std_logic;
      L1ASRST      : out std_logic;
      TTCCAL       : out std_logic_vector(2 downto 0)
      );        
  end component;

  -- Temporary debugging
  component ila_1 is
    port (
      clk : in std_logic := '0';
      probe0 : in std_logic_vector(127 downto 0) := (others=> '0')
      );
  end component;

  component ila_2 is
    port (
      clk : in std_logic := '0';
      probe0 : in std_logic_vector(383 downto 0) := (others=> '0')
      );
  end component;

  signal LOGICL : std_logic := '0';
  signal LOGICH : std_logic := '1';

  signal plsinjen, plsinjen_inv : std_logic := '0';

  signal CAL_LCT       : std_logic;
  signal cal_gtrg     : std_logic;

  -- CCBCODE outputs
  signal bc0                       : std_logic;
  signal ttccal                    : std_logic_vector(2 downto 0);

  -- internal signals
  signal cafifo_l1a_match_in_inner : std_logic_vector(NCFEB+2 downto 0);
  signal cafifo_push               : std_logic;  -- PUSH from TRGCNTRL to CAFIFO
  signal cafifo_l1a_match_out_inner : std_logic_vector(NCFEB+2 downto 1);
  signal cafifo_l1a_cnt_out         : std_logic_vector(23 downto 0);
  signal cafifo_l1a_dav_out         : std_logic_vector(NCFEB+2 downto 1);
  signal cafifo_bx_cnt_out          : std_logic_vector(11 downto 0);
  signal cafifo_lost_pckt_out       : std_logic_vector(NCFEB+2 downto 1);
  signal cafifo_lone                : std_logic;

  signal bxrst, ccb_bxrst, ccb_bx0 : std_logic;
  signal status : std_logic_vector(47 downto 0) := (others => '0');
  signal rdffnxt : std_logic := '0';    -- from MBV

  -- CONTROL outputs
  signal control_debug_full   : std_logic_vector(143 downto 0);
  signal cafifo_pop           : std_logic := '0';
  signal eof                  : std_logic := '0';
  signal ddu_data_inner       : std_logic_vector(15 downto 0);
  signal ddu_data_valid_inner : std_logic := 'L';

  signal joef : std_logic_vector(NCFEB+2 downto 1);
  signal daqmbid : std_logic_vector(11 downto 0);

  signal diag_trigctrl : std_logic_vector(26 downto 0);
  signal ila_data1 : std_logic_vector(127 downto 0);
  signal ila_data2 : std_logic_vector(383 downto 0);

begin

  ----------------------------------
  -- Generate plsinjen (why is this oscillating?)
  ----------------------------------
  --current ODMB delays PLSINJEN after power-on for a couple clock cycles
  FDCE_plsinjen : FDCE port map(D => plsinjen_inv, C => CMSCLK, CE => '1', CLR => '0', Q => plsinjen);
  plsinjen_inv <= not plsinjen;

  ----------------------------------
  -- sub-modules
  ----------------------------------

  CALIBTRG_PM : CALIBTRG
    port map (
      CMSCLK => CMSCLK,
      CLK80 => DDUCLK,
      RST => RST, 
      PLSINJEN => PLSINJEN, 
      CCBPLS => '0',              --TODO generate from CCB input
      CCBINJ => '0',              --TODO generate from CCB input
      FPLS => TEST_CCBPLS,
      FINJ => TEST_CCBINJ, 
      FPED => TEST_CCBPED, 
      PRELCT => '0',              --unused
      PREGTRG => '0',             --unused
      INJ_DLY => INJ_DLY, 
      EXT_DLY => EXT_DLY, 
      CALLCT_DLY => CALLCT_DLY, 
      LCT_L1A_DLY => LCT_L1A_DLY, 
      RNDMPLS => '0',             --unused
      RNDMGTRG => '0',            --unused
      PEDESTAL => open,           --unused
      CAL_GTRG => cal_gtrg,           
      CALLCT => cal_lct,             --TODO connect to TRGCNTRL
      INJBACK => DCFEB_INJPULSE,
      PLSBACK => DCFEB_EXTPULSE,
      LCTRQST => open, 
      INJPLS => open              --unused
      );

 
  TRGCNTRL_PM : TRGCNTRL
    generic map (
      NCFEB => NCFEB
      )
    port map (
      CLK           => CMSCLK,
      RAW_L1A       => raw_l1a,
      RAW_LCT       => rawlct,
      CAL_LCT       => cal_lct,
      CAL_L1A       => cal_gtrg,
      LCT_L1A_DLY   => lct_l1a_dly,
      OTMB_PUSH_DLY => otmb_push_dly,
      ALCT_PUSH_DLY => alct_push_dly,
      PUSH_DLY      => push_dly,
      ALCT_DAV      => alct_dav,
      OTMB_DAV      => otmb_dav,

      CAL_MODE      => CAL_MODE,
      KILL          => kill(NCFEB+2 downto 1),
      PEDESTAL      => pedestal,
      PEDESTAL_OTMB => pedestal_otmb,

      ALCT_DAV_SYNC_OUT => ALCT_DAV_SYNC_OUT,
      OTMB_DAV_SYNC_OUT => OTMB_DAV_SYNC_OUT,

      DCFEB_L1A       => dcfeb_l1a,
      DCFEB_L1A_MATCH => dcfeb_l1a_match,
      FIFO_PUSH       => cafifo_push,
      FIFO_L1A_MATCH  => cafifo_l1a_match_in_inner,
      LCT_ERR         => lct_err,
      DIAGOUT         => diag_trigctrl
      );

  CAFIFO_PM : CAFIFO
    generic map (
      NCFEB => NCFEB,
      CAFIFO_SIZE => CAFIFO_SIZE
      )
    port map(
      --CSP_FREE_AGENT_PORT_LA_CTRL => CSP_FREE_AGENT_PORT_LA_CTRL,
      clk        => CMSCLK,
      dduclk     => DDUCLK,
      l1acnt_rst => l1acnt_rst,
      bxcnt_rst  => bxcnt_rst,

      BC0        => bc0,
      CCB_BX0    => ccb_bx0,
      BXRST      => ccb_bxrst,
      BX_DLY     => BX_DLY,
      PUSH_DLY   => push_dly,

      pop          => cafifo_pop,
      l1a          => cafifo_push,
      l1a_match_in => cafifo_l1a_match_in_inner(NCFEB+2 downto 1),

      eof_data     => eof_data,

      cafifo_l1a_match => cafifo_l1a_match_out_inner,
      cafifo_l1a_cnt   => cafifo_l1a_cnt_out,
      cafifo_l1a_dav   => cafifo_l1a_dav_out,
      cafifo_bx_cnt    => cafifo_bx_cnt_out,
      cafifo_lost_pckt => cafifo_lost_pckt_out,
      cafifo_lone      => cafifo_lone,

      cafifo_prev_next_l1a_match => cafifo_prev_next_l1a_match,
      cafifo_prev_next_l1a       => cafifo_prev_next_l1a,
      control_debug              => control_debug_full,
      cafifo_debug               => cafifo_debug,
      cafifo_wr_addr             => cafifo_wr_addr,
      cafifo_rd_addr             => cafifo_rd_addr
      );

  CONTROL_FSM_PM : CONTROL_FSM
    generic map(
      NCFEB => NCFEB
      )
    port map(
      --CSP_CONTROL_FSM_PORT_LA_CTRL => CSP_CONTROL_FSM_PORT_LA_CTRL,
      CLK    => DDUCLK,
      CLKCMS => CMSCLK,
      RST    => l1acnt_rst,
      STATUS => status,

      -- From DMB_VME
      RDFFNXT => rdffnxt,  -- from MBV (currently assigned as a signal to '0')
      KILL => KILL,
      
      -- to GigaBit Link
      DOUT => ddu_data_inner,
      DAV  => ddu_data_valid_inner,

      -- to Data FIFOs
      OEFIFO_B  => FIFO_OE_B,
      RENFIFO_B => FIFO_RE_B,

      -- from Data FIFOs
      FIFO_HALF_FULL => fifo_half_full,
      FFOR_B         => fifo_empty,
      DATAIN         => FIFO_DOUT(15 downto 0),
      DATAIN_LAST    => FIFO_DOUT(17),

      -- From JTAGCOM
      JOEF => joef,       -- from LOADFIFO

      -- From CONFREG and GA
      DAQMBID => daqmbid,
      AUTOKILLED_DCFEBS => AUTOKILLED_DCFEBS,

      -- FROM SW1
      GIGAEN => LOGICH,

      -- TO CAFIFO
      FIFO_POP => cafifo_pop,

      -- TO PCFIFO
      EOF => eof,

      -- DEBUG
      control_debug => control_debug_full,

      -- FROM CAFIFO
      cafifo_l1a_dav   => cafifo_l1a_dav_out,
      cafifo_l1a_match => cafifo_l1a_match_out_inner,
      cafifo_l1a_cnt   => cafifo_l1a_cnt_out,
      cafifo_bx_cnt    => cafifo_bx_cnt_out,
      cafifo_lost_pckt => cafifo_lost_pckt_out,
      cafifo_lone      => cafifo_lone
      );

  CCBCODE_PM : CCBCODE
    port map(
      CCB_CMD      => CCB_CMD,
      CCB_CMD_S    => CCB_CMD_S,
      CCB_DATA     => CCB_DATA,
      CCB_DATA_S   => CCB_DATA_S,
      CMSCLK       => CMSCLK,
      CCB_BXRST_B  => CCB_BXRST_B,
      CCB_BX0_B    => CCB_BX0_B,
      CCB_L1ARST_B => CCB_L1ARST_B,
      CCB_CLKEN    => CCB_CLKEN,

      BX0          => open,
      BXRST        => open,
      L1ARST       => open,
      CLKEN        => open,
      BC0          => bc0,
      L1ASRST      => open,
      TTCCAL       => ttccal -- to be connected
      );

  CAFIFO_L1A           <= cafifo_push;
  CAFIFO_L1A_MATCH_IN  <= cafifo_l1a_match_in_inner(NCFEB+2 downto 1);
  CAFIFO_L1A_MATCH_OUT <= cafifo_l1a_match_out_inner;
  CAFIFO_L1A_DAV       <= cafifo_l1a_dav_out;
  CAFIFO_L1A_CNT       <= cafifo_l1a_cnt_out;
  CAFIFO_BX_CNT        <= cafifo_bx_cnt_out;

  ccb_bx0 <= not ccb_bx0_b;
  ccb_bxrst <= not ccb_bxrst_b;
  control_debug <= control_debug_full(15 downto 0);

  DDU_DATA       <= ddu_data_inner;
  DDU_DATA_VALID <= ddu_data_valid_inner;

  daqmbid(11 downto 4) <= crateid;
  daqmbid(3 downto 0)  <= not ga(4 downto 1);  -- GA0 not included so that this is ODMB counter

  -- ILA
  ila_data1(3 downto 0)   <= otmb_dav & alct_dav & rawlct(0) & raw_l1a; -- raw signal
  ila_data1(10 downto 4)  <= rawlct(7 downto 1);  
  ila_data1(28 downto 11) <= diag_trigctrl(17 downto 0);
  ila_data1(37 downto 29) <= cafifo_l1a_match_in_inner(9 downto 1);
  ila_data1(46 downto 38) <= control_debug_full(41 downto 33); -- CAFIFO_L1A_MATCH
  ila_data1(55 downto 47) <= control_debug_full(50 downto 42); -- CAFIFO_L1A_DAV
  ila_data1(56)           <= control_debug_full(16); -- dav_inner
  ila_data1(59 downto 57) <= cal_lct & cal_gtrg & cal_mode;
  ila_data1(66 downto 61) <= LCT_L1A_DLY;
  ila_data1(72 downto 67) <= std_logic_vector(to_unsigned(OTMB_PUSH_DLY, 6));
  ila_data1(78 downto 73) <= std_logic_vector(to_unsigned(ALCT_PUSH_DLY, 6));
  ila_data1(84 downto 79) <= std_logic_vector(to_unsigned(PUSH_DLY, 6));
  ila_data1(100 downto 85)  <= control_debug_full(69 downto 54); -- dout_inner
  ila_data1(104 downto 101) <= control_debug_full(20 downto 17); -- current_state_svl
  ila_data1(109 downto 105) <= control_debug_full(25 downto 21); -- dev_cnt_svl
  ila_data1(110)            <= control_debug_full(32);           -- q_datain_last

  ila_odmb_ctrl_inst1 : ila_1
    port map(
      clk => DDUCLK,
      probe0 => ila_data1
      );

  ila_data2(119 downto 0) <= control_debug_full(135 downto 16);

  -- ila_odmb_ctrl_inst2 : ila_2
  --   port map(
  --     clk => DDUCLK,
  --     probe0 => ila_data2
  --     );

end Behavioral;
