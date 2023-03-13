library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_misc.all;

library unisim;
use unisim.vcomponents.all;

library work;
use work.ucsb_types.all;

entity odmb_status is
  generic (
    NCFEB               : integer range 1 to 7 := 7  -- Number of DCFEBS, 7 for ME1/1, 5
    );
  port (
    ODMB_STAT_SEL       : in  std_logic_vector(7 downto 0);
    ODMB_STAT_DATA      : out std_logic_vector(15 downto 0);

    CMSCLK              : in std_logic;
    DDUCLK              : in std_logic;
    DCFEBCLK            : in std_logic;

    DCFEB_CRC_VALID     : in std_logic_vector(NCFEB downto 1);
    DCFEB_RXD_VALID     : in std_logic_vector(NCFEB downto 1);
    DCFEB_BAD_RX        : in std_logic_vector(NCFEB downto 1);
    RAW_LCT             : in std_logic_vector(NCFEB downto 0);
    ALCT_DAV            : in std_logic;
    OTMB_DAV            : in std_logic;
    RAW_L1A             : in std_logic;
    DCFEB_L1A           : in std_logic;

    EOF_DATA            : in std_logic_vector(NCFEB+2 downto 1);
    FIFO_RE_B           : in std_logic_vector(NCFEB+2 downto 1);
    INTO_FIFO_DAV       : in std_logic_vector(NCFEB+2 downto 1);
    CAFIFO_L1A_MATCH    : in std_logic_vector(NCFEB+2 downto 1);
    CAFIFO_L1A_DAV      : in std_logic_vector(NCFEB+2 downto 1);

    CAFIFO_L1A_CNT      : in std_logic_vector(23 downto 0);
    CAFIFO_BX_CNT       : in std_logic_vector(11 downto 0);

    CCB_CMD_BXEV        : in  std_logic_vector(7 downto 0);
    CCB_CMD_S           : in  std_logic;       -- ccbcmnd(6) - from J3
    CCB_DATA            : in  std_logic_vector(7 downto 0);  -- ccbdata(7 downto 0) - from J3
    CCB_DATA_S          : in  std_logic;       -- ccbdata(8) - from J3
    CCB_RSV             : in  std_logic_vector(10 downto 0);
    CCB_OTHER           : in  std_logic_vector(10 downto 0);

    L1ACNT_RST          : in std_logic;
    PON_RESET           : in std_logic;
    RESET               : in std_logic  --! Global reset
    );
end odmb_status;

architecture ODMB_STATUS_ARCH of odmb_status is


  --------------------------------------
  -- ODMB status signals
  --------------------------------------
  -- Counter arrays (maximum length has to be used)
  signal goodcrc_cnt         : t_std16_array(7 downto 1);
  signal dcfeb_bad_rx_cnt    : t_std16_array(7 downto 1);
  signal dcfeb_dvalid_cnt    : t_std16_array(7 downto 1); -- replacement for cafifo dav count
  signal dcfeb_badcrc_cnt    : t_std16_array(7 downto 1);

  signal into_fifo_dav_cnt   : t_std16_array(9 downto 1);
  signal l1a_match_cnt       : t_std16_array(9 downto 1);
  signal data_fifo_re_cnt    : t_std16_array(9 downto 1);
  signal eof_data_cnt        : t_std16_array(9 downto 1);
  signal cafifo_l1a_dav_cnt  : t_std16_array(9 downto 1);
  signal lct_l1a_gap         : t_std16_array(9 downto 1);
  signal raw_lct_cnt         : t_std16_array(9 downto 1);

  signal fifo_re             : std_logic_vector(NCFEB+2 downto 1);
  signal odmb_data           : std_logic_vector(15 downto 0);

  -- Helper relay signals for making it always 16 bit long under different NCFEB number
  signal cafifo_l1a_match_data : std_logic_vector(15 downto 0) := (others => '0');
  signal cafifo_l1a_dav_data   : std_logic_vector(15 downto 0) := (others => '0');

  signal dcfeb_l1a_cnt         : std_logic_vector(15 downto 0);
  signal unsync_l1a_cnt        : std_logic_vector(15 downto 0);

  -- CCB production test signals
  signal ccb_cmd_reg     : std_logic_vector(15 downto 0) := (others => '0');
  signal ccb_data_reg    : std_logic_vector(15 downto 0) := (others => '0');
  signal ccb_rsv_reg     : std_logic_vector(15 downto 0) := (others => '0');
  signal ccb_other_reg   : std_logic_vector(15 downto 0) := (others => '0');
  signal ccb_rsv_reg_b   : std_logic_vector(15 downto 0) := (others => '0');
  signal ccb_other_reg_b : std_logic_vector(15 downto 0) := (others => '0');

begin

  ODMB_STAT_DATA <= odmb_data;

  cafifo_l1a_match_data(NCFEB+1 downto 0) <= CAFIFO_L1A_MATCH;
  cafifo_l1a_dav_data(NCFEB+1 downto 0) <= CAFIFO_L1A_DAV;

  c_odmb_status : process (ODMB_STAT_SEL)
  begin

    case ODMB_STAT_SEL is

      -- when x"00" => odmb_data <= odmb_status;
      -- when x"01" => odmb_data <= odmb_ctrl_reg;
      -- when x"02" => odmb_data <= cafifo_debug;  --cafifo_empty & cafifo_full & cafifo_state_slv & timeout_state_1
      -- when x"03" => odmb_data <= cafifo_prev_next_l1a;
      -- when x"04" => odmb_data <= cafifo_prev_next_l1a_match;
      -- when x"05" => odmb_data <= control_debug;  --'0' & dev_cnt_svl & '0' & hdr_tail_cnt_svl & current_state_svl;
      -- when x"06" => odmb_data <= x"7E57";
      -- when x"07" => odmb_data <= x"0000";

      -- when x"08" => odmb_data <= "0000" & dcfeb_adc_mask(3);
      -- when x"09" => odmb_data <= dcfeb_fsel(3)(15 downto 0);
      -- when x"0A" => odmb_data <= dcfeb_fsel(3)(31 downto 16);
      -- when x"0B" => odmb_data <= "00" & dcfeb_jtag_ir(3) & "000" & dcfeb_fsel(3)(31);

      -- when x"0C" => odmb_data <= "0000" & dcfeb_adc_mask(4);
      -- when x"0D" => odmb_data <= dcfeb_fsel(4)(15 downto 0);
      -- when x"0E" => odmb_data <= dcfeb_fsel(4)(31 downto 16);
      -- when x"0F" => odmb_data <= "00" & dcfeb_jtag_ir(4) & "000" & dcfeb_fsel(4)(31);

      -- when x"10" => odmb_data <= "0000" & dcfeb_adc_mask(5);
      -- when x"11" => odmb_data <= dcfeb_fsel(5)(15 downto 0);
      -- when x"12" => odmb_data <= dcfeb_fsel(5)(31 downto 16);
      -- when x"13" => odmb_data <= "00" & dcfeb_jtag_ir(5) & "000" & dcfeb_fsel(5)(31);

      -- when x"14" => odmb_data <= "0000" & dcfeb_adc_mask(6);
      -- when x"15" => odmb_data <= dcfeb_fsel(6)(15 downto 0);
      -- when x"16" => odmb_data <= dcfeb_fsel(6)(31 downto 16);
      -- when x"17" => odmb_data <= "00" & dcfeb_jtag_ir(6) & "000" & dcfeb_fsel(6)(31);

      -- when x"18" => odmb_data <= "0000" & dcfeb_adc_mask(7);
      -- when x"19" => odmb_data <= dcfeb_fsel(7)(15 downto 0);
      -- when x"1A" => odmb_data <= dcfeb_fsel(7)(31 downto 16);
      -- when x"1B" => odmb_data <= "00" & dcfeb_jtag_ir(7) & "000" & dcfeb_fsel(7)(31);

      when x"1C" => odmb_data <= x"0000";
      when x"1D" => odmb_data <= x"0000";
      when x"1E" => odmb_data <= x"0000";
      when x"1F" => odmb_data <= x"0000";

      -- when x"20" => odmb_data <= "0000000000" & VME_GAP_B & VME_GA_B;

      when x"21" => odmb_data <= l1a_match_cnt(1);
      when x"22" => odmb_data <= l1a_match_cnt(2);
      when x"23" => odmb_data <= l1a_match_cnt(3);
      when x"24" => odmb_data <= l1a_match_cnt(4);
      when x"25" => odmb_data <= l1a_match_cnt(5);
      when x"26" => odmb_data <= l1a_match_cnt(6);
      when x"27" => odmb_data <= l1a_match_cnt(7);
      when x"28" => odmb_data <= l1a_match_cnt(8);
      when x"29" => odmb_data <= l1a_match_cnt(9);

      -- when x"2A" => odmb_data <= std_logic_vector(to_unsigned(alct_push_dly, 16));
      -- when x"2B" => odmb_data <= std_logic_vector(to_unsigned(otmb_push_dly, 16));
      -- when x"2C" => odmb_data <= std_logic_vector(to_unsigned(push_dly, 16));
      -- when x"2D" => odmb_data <= "0000000000" & lct_l1a_dly;
      -- when x"2E" => odmb_data <= ts_out(15 downto 0);
      -- when x"2F" => odmb_data <= ts_out(31 downto 16);

      when x"31" => odmb_data <= lct_l1a_gap(1);
      when x"32" => odmb_data <= lct_l1a_gap(2);
      when x"33" => odmb_data <= lct_l1a_gap(3);
      when x"34" => odmb_data <= lct_l1a_gap(4);
      when x"35" => odmb_data <= lct_l1a_gap(5);
      when x"36" => odmb_data <= lct_l1a_gap(6);
      when x"37" => odmb_data <= lct_l1a_gap(7);
      when x"38" => odmb_data <= lct_l1a_gap(8); -- l1a_otmbdav_gap
      when x"39" => odmb_data <= lct_l1a_gap(9); -- l1a_alctdav_gap

      when x"3A" => odmb_data <= x"00" & cafifo_l1a_cnt(23 downto 16); -- upper  8/24 bits
      when x"3B" => odmb_data <= cafifo_l1a_cnt(15 downto 0);          -- lower 16/24 bits
      when x"3C" => odmb_data <= x"0" & cafifo_bx_cnt;
      -- when x"3D" => odmb_data <= cafifo_rd_addr & cafifo_wr_addr;
      when x"3E" => odmb_data <= cafifo_l1a_match_data;
      when x"3F" => odmb_data <= dcfeb_l1a_cnt;

      when x"41" => odmb_data <= into_fifo_dav_cnt(1);
      when x"42" => odmb_data <= into_fifo_dav_cnt(2);
      when x"43" => odmb_data <= into_fifo_dav_cnt(3);
      when x"44" => odmb_data <= into_fifo_dav_cnt(4);
      when x"45" => odmb_data <= into_fifo_dav_cnt(5);
      when x"46" => odmb_data <= into_fifo_dav_cnt(6);
      when x"47" => odmb_data <= into_fifo_dav_cnt(7);
      when x"48" => odmb_data <= into_fifo_dav_cnt(8);
      when x"49" => odmb_data <= into_fifo_dav_cnt(9);

      -- when x"4A" => odmb_data <= ddu_eof_cnt;  -- Number of packets sent to DDU
      -- when x"4B" => odmb_data <= pc_data_valid_cnt;  -- Number of packets sent to PC
      -- --when x"4C" => odmb_data <= data_fifo_oe_cnt(1);  -- from control to FIFOs in top
      -- when x"4D" => odmb_data <= "00" & x"0" & cafifo_l1a_match_out when NCFEB = 7 else
      --                            '0' & x"00" & cafifo_l1a_match_out when NCFEB = 5 else
      --                            (others => '0');
      when x"4E" => odmb_data <= cafifo_l1a_dav_data;
      -- when x"4F" => odmb_data <= qpll_locked_cnt;

      when x"51" => odmb_data <= data_fifo_re_cnt(1);  -- from control to FIFOs in top
      when x"52" => odmb_data <= data_fifo_re_cnt(2);  -- from control to FIFOs in top
      when x"53" => odmb_data <= data_fifo_re_cnt(3);  -- from control to FIFOs in top
      when x"54" => odmb_data <= data_fifo_re_cnt(4);  -- from control to FIFOs in top
      when x"55" => odmb_data <= data_fifo_re_cnt(5);  -- from control to FIFOs in top
      when x"56" => odmb_data <= data_fifo_re_cnt(6);  -- from control to FIFOs in top
      when x"57" => odmb_data <= data_fifo_re_cnt(7);  -- from control to FIFOs in top
      when x"58" => odmb_data <= data_fifo_re_cnt(8);  -- from control to FIFOs in top
      when x"59" => odmb_data <= data_fifo_re_cnt(9);  -- from control to FIFOs in top

      when x"5A" => odmb_data <= ccb_cmd_reg;
      when x"5B" => odmb_data <= ccb_data_reg;
      when x"5C" => odmb_data <= ccb_other_reg;
      when x"5D" => odmb_data <= ccb_rsv_reg;
      when x"5F" => odmb_data <= unsync_l1a_cnt;

      when x"61" => odmb_data <= goodcrc_cnt(1);
      when x"62" => odmb_data <= goodcrc_cnt(2);
      when x"63" => odmb_data <= goodcrc_cnt(3);
      when x"64" => odmb_data <= goodcrc_cnt(4);
      when x"65" => odmb_data <= goodcrc_cnt(5);
      when x"66" => odmb_data <= goodcrc_cnt(6);
      when x"67" => odmb_data <= goodcrc_cnt(7);

      when x"71" => odmb_data <= raw_lct_cnt(1);
      when x"72" => odmb_data <= raw_lct_cnt(2);
      when x"73" => odmb_data <= raw_lct_cnt(3);
      when x"74" => odmb_data <= raw_lct_cnt(4);
      when x"75" => odmb_data <= raw_lct_cnt(5);
      when x"76" => odmb_data <= raw_lct_cnt(6);
      when x"77" => odmb_data <= raw_lct_cnt(7);
      when x"78" => odmb_data <= raw_lct_cnt(8);
      when x"79" => odmb_data <= raw_lct_cnt(9);

      when x"81" => odmb_data <= eof_data_cnt(1);  -- Number of packets arrived in full
      when x"82" => odmb_data <= eof_data_cnt(2);  -- Number of packets arrived in full
      when x"83" => odmb_data <= eof_data_cnt(3);  -- Number of packets arrived in full
      when x"84" => odmb_data <= eof_data_cnt(4);  -- Number of packets arrived in full
      when x"85" => odmb_data <= eof_data_cnt(5);  -- Number of packets arrived in full
      when x"86" => odmb_data <= eof_data_cnt(6);  -- Number of packets arrived in full
      when x"87" => odmb_data <= eof_data_cnt(7);  -- Number of packets arrived in full
      when x"88" => odmb_data <= eof_data_cnt(8);  -- Number of packets arrived in full
      when x"89" => odmb_data <= eof_data_cnt(9);  -- Number of packets arrived in full

      when x"91" => odmb_data <= cafifo_l1a_dav_cnt(1);  -- Times data has been available
      when x"92" => odmb_data <= cafifo_l1a_dav_cnt(2);  -- Times data has been available
      when x"93" => odmb_data <= cafifo_l1a_dav_cnt(3);  -- Times data has been available
      when x"94" => odmb_data <= cafifo_l1a_dav_cnt(4);  -- Times data has been available
      when x"95" => odmb_data <= cafifo_l1a_dav_cnt(5);  -- Times data has been available
      when x"96" => odmb_data <= cafifo_l1a_dav_cnt(6);  -- Times data has been available
      when x"97" => odmb_data <= cafifo_l1a_dav_cnt(7);  -- Times data has been available
      when x"98" => odmb_data <= cafifo_l1a_dav_cnt(8);  -- Times data has been available
      when x"99" => odmb_data <= cafifo_l1a_dav_cnt(9);  -- Times data has been available

      when x"A1" => odmb_data <= dcfeb_badcrc_cnt(1);
      when x"A2" => odmb_data <= dcfeb_badcrc_cnt(2);
      when x"A3" => odmb_data <= dcfeb_badcrc_cnt(3);
      when x"A4" => odmb_data <= dcfeb_badcrc_cnt(4);
      when x"A5" => odmb_data <= dcfeb_badcrc_cnt(5);
      when x"A6" => odmb_data <= dcfeb_badcrc_cnt(6);
      when x"A7" => odmb_data <= dcfeb_badcrc_cnt(7);

      -- when x"A8" => odmb_data <= ddu_txplllkdet_b_cnt; -- Times the DDU TX PLL "loses lock"
      -- when x"A9" => odmb_data <= ddu_bad_rx_cnt;       -- Times the DDU RX has an error
      -- when x"AA" => odmb_data <= ddu_bad_rx_bit_cnt;   -- Number of bit errors in the DDU RX
      -- when x"AB" => odmb_data <= pc_bad_rx_cnt;        -- Times the PC RX has an error
      -- when x"AC" => odmb_data <= pc_bad_rx_bit_cnt;    -- Number of bit errors in the PC RX

      when x"B1" => odmb_data <= dcfeb_bad_rx_cnt(1);
      when x"B2" => odmb_data <= dcfeb_bad_rx_cnt(2);
      when x"B3" => odmb_data <= dcfeb_bad_rx_cnt(3);
      when x"B4" => odmb_data <= dcfeb_bad_rx_cnt(4);
      when x"B5" => odmb_data <= dcfeb_bad_rx_cnt(5);
      when x"B6" => odmb_data <= dcfeb_bad_rx_cnt(6);
      when x"B7" => odmb_data <= dcfeb_bad_rx_cnt(7);
      -- when x"B8" => odmb_data <= x"00" & '0' & autokilled_dcfebs; -- DCFEBs auto-killed due to fiber errors or too long packets
      -- when x"B9" => odmb_data <= x"00" & '0' & autokilled_dcfebs_fiber; -- DCFEBs auto-killed due to fiber errors

      when others => odmb_data <= (others => '1');
    end case;
  end process;

  -------------------------------------------------------------------------------------------
  -- ODMB status signal generations
  -------------------------------------------------------------------------------------------

  fifo_re <= not FIFO_RE_B;

  -- TODO: unfinished counting to be filled
  DCFEB_RXSTAT_CNT : for dev in 1 to NCFEB generate
  begin
    -- Counters for DCFEB only
    C_GODDCRC_CNT : COUNT_EDGES  port map(COUNT => goodcrc_cnt(dev),      CLK => DCFEBCLK, RST => RESET, DIN => DCFEB_CRC_VALID(dev));
    C_DVALID_CNT  : COUNT_EDGES  port map(COUNT => dcfeb_dvalid_cnt(dev), CLK => DCFEBCLK, RST => RESET, DIN => DCFEB_RXD_VALID(dev));
    C_BAD_RX_CNT  : COUNT_WINDOW port map(COUNT => dcfeb_bad_rx_cnt(dev), CLK => DCFEBCLK, RST => RESET, DIN => DCFEB_BAD_RX(dev));

    -- Counters for DCFEB, ALCT and OTMB
    RAWLCT_CNT    : COUNT_EDGES port map(COUNT => raw_lct_cnt(dev),        CLK => CMSCLK, RST => RESET, DIN => RAW_LCT(dev));
    PACKET_CNT    : COUNT_EDGES port map(COUNT => into_fifo_dav_cnt(dev),  CLK => CMSCLK, RST => RESET, DIN => INTO_FIFO_DAV(dev));
    FIFORE_CNT    : COUNT_EDGES port map(COUNT => data_fifo_re_cnt(dev),   CLK => DDUCLK, RST => RESET, DIN => FIFO_RE(dev));
    DATAEOF_CNT   : COUNT_EDGES port map(COUNT => eof_data_cnt(dev),       CLK => CMSCLK, RST => RESET, DIN => EOF_DATA(dev));
    L1AMATCH_CNT  : COUNT_EDGES port map(COUNT => l1a_match_cnt(dev),      CLK => CMSCLK, RST => RESET, DIN => CAFIFO_L1A_MATCH(dev));
    CAFIFODAV_CNT : COUNT_EDGES port map(COUNT => cafifo_l1a_dav_cnt(dev), CLK => DDUCLK, RST => RESET, DIN => CAFIFO_L1A_DAV(dev));
    LCTL1A_GAP    : GAP_COUNTER generic map(MAX_CYCLES => 200)
      port map(GAP_COUNT => lct_l1a_gap(dev), CLK => CMSCLK, RST => RESET, SIGNAL1 => RAW_LCT(dev), SIGNAL2 => DCFEB_L1A);

    dcfeb_badcrc_cnt(dev) <= std_logic_vector( unsigned(eof_data_cnt(dev)) - unsigned(goodcrc_cnt(dev)) );
  end generate DCFEB_RXSTAT_CNT;

  -- Counting for OTMB: keep them at position 8
  RAWLCT_CNT8    : COUNT_EDGES port map(COUNT => raw_lct_cnt(8),        CLK => CMSCLK, RST => RESET, DIN => OTMB_DAV);
  FIFORE_CNT8    : COUNT_EDGES port map(COUNT => data_fifo_re_cnt(8),   CLK => DDUCLK, RST => RESET, DIN => FIFO_RE(NCFEB+1));
  PACKET_CNT8    : COUNT_EDGES port map(COUNT => into_fifo_dav_cnt(8),  CLK => CMSCLK, RST => RESET, DIN => INTO_FIFO_DAV(NCFEB+1));
  DATAEOF_CNT8   : COUNT_EDGES port map(COUNT => eof_data_cnt(8),       CLK => CMSCLK, RST => RESET, DIN => EOF_DATA(NCFEB+1));
  L1AMATCH_CNT8  : COUNT_EDGES port map(COUNT => l1a_match_cnt(8),      CLK => CMSCLK, RST => RESET, DIN => CAFIFO_L1A_MATCH(NCFEB+1));
  CAFIFODAV_CNT8 : COUNT_EDGES port map(COUNT => cafifo_l1a_dav_cnt(8), CLK => DDUCLK, RST => RESET, DIN => CAFIFO_L1A_DAV(NCFEB+1));
  LCTL1A_GAP8    : GAP_COUNTER generic map(MAX_CYCLES => 200)
    port map(GAP_COUNT => lct_l1a_gap(8), CLK => CMSCLK, RST => RESET, SIGNAL1 => RAW_L1A, SIGNAL2 => ALCT_DAV);

  -- Counting for ALCT: keep them at position 9
  RAWLCT_CNT9    : COUNT_EDGES port map(COUNT => raw_lct_cnt(9),        CLK => CMSCLK, RST => RESET, DIN => ALCT_DAV);
  FIFORE_CNT9    : COUNT_EDGES port map(COUNT => data_fifo_re_cnt(9),   CLK => DDUCLK, RST => RESET, DIN => FIFO_RE(NCFEB+2));
  PACKET_CNT9    : COUNT_EDGES port map(COUNT => into_fifo_dav_cnt(9),  CLK => CMSCLK, RST => RESET, DIN => INTO_FIFO_DAV(NCFEB+2));
  DATAEOF_CNT9   : COUNT_EDGES port map(COUNT => eof_data_cnt(9),       CLK => CMSCLK, RST => RESET, DIN => EOF_DATA(NCFEB+2));
  L1AMATCH_CNT9  : COUNT_EDGES port map(COUNT => l1a_match_cnt(9),      CLK => CMSCLK, RST => RESET, DIN => CAFIFO_L1A_MATCH(NCFEB+2));
  CAFIFODAV_CNT9 : COUNT_EDGES port map(COUNT => cafifo_l1a_dav_cnt(9), CLK => DDUCLK, RST => RESET, DIN => CAFIFO_L1A_DAV(NCFEB+2));
  LCTL1A_GAP9    : GAP_COUNTER generic map(MAX_CYCLES => 200)
    port map(GAP_COUNT => lct_l1a_gap(9), CLK => CMSCLK, RST => RESET, SIGNAL1 => RAW_L1A, SIGNAL2 => OTMB_DAV);

  -- Counting for DCFEB reduced signal
  DCFEBL1A_CNT   : COUNT_EDGES port map(COUNT => dcfeb_l1a_cnt,  CLK => CMSCLK, RST => L1ACNT_RST, DIN => DCFEB_L1A);
  UNSYNCL1A_CNT  : COUNT_EDGES port map(COUNT => unsync_l1a_cnt, CLK => CMSCLK, RST => PON_RESET,  DIN => DCFEB_L1A);

  -------------------------------------------------------------------------------------------
  -- CCB count generations
  -------------------------------------------------------------------------------------------
  GEN_CCB : for index in 0 to 7 generate
    FDCMD : FDC port map(Q => ccb_cmd_reg(index),  C => CCB_CMD_S,  CLR => RESET, D => CCB_CMD_BXEV(index));
    FDDAT : FDC port map(Q => ccb_data_reg(index), C => CCB_DATA_S, CLR => RESET, D => CCB_DATA(index));
  end generate GEN_CCB;

  GEN_CCB_FD : for index in 0 to 10 generate
    FDOTHER : FDC port map(Q => ccb_other_reg(index), C => CCB_OTHER(index), CLR => RESET, D => ccb_other_reg_b(index));
    FDRSV   : FDC port map(Q => ccb_rsv_reg(index),   C => CCB_RSV(index),   CLR => RESET, D => ccb_rsv_reg_b(index));
    ccb_other_reg_b(index) <= not ccb_other_reg(index);
    ccb_rsv_reg_b(index)   <= not ccb_rsv_reg(index);
  end generate GEN_CCB_FD;


end ODMB_STATUS_ARCH;
