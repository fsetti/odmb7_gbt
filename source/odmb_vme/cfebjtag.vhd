library ieee;
library work;
library UNISIM;
use UNISIM.vcomponents.all;
use work.Latches_Flipflops.all;
use ieee.std_logic_1164.all;
use work.ucsb_types.all;

--! @brief module handling JTAG (slow control) communication to (x)DCFEBs within ODMB VME
--! @details Supported VME commands:
--! * W 1Y00 shift Y+1 data bits with no JTAG header or tailer
--! * W 1Y04 shift Y+1 data bits with JTAG header 
--! * W 1Y08 shift Y+1 data bits with JTAG tailer
--! * W 1Y0C shift Y+1 data bits with JTAG header and tailer
--! * R 1014 read last data bits shifted into TDO register
--! * W 1018 send JTAG reset pattern
--! * W 1Y1C identical to W 1Y3C
--! * W 1020 select (x)DCFEBs; one bit per (x)DCFEB
--! * R 1024 read selected (x)DCFEBs
--! * W 1Y30 shift Y+1 instruction bits with no JTAG header or tailer
--! * W 1Y34 shift Y+1 instruction bits with JTAG header
--! * W 1Y38 shift Y+1 instruction bits with JTAG tailer
--! * W 1Y3C shift Y+1 instruction bits with JTAG header and tailer
--! * W 1Y48 shift Y+1 instruction bits with special JTAG tailer
--! * W 1Y4C shift Y+1 instruction bits with JTAG header and special JTAG tailer
entity CFEBJTAG is
  generic (
    NCFEB   : integer range 1 to 7 := 7  -- Number of DCFEBS, 7 for ME1/1, 5
    );
  port (
    FASTCLK : in std_logic;                           --! 40 MHz clock. Currently unused.
    SLOWCLK : in std_logic;                           --! 1.25MHz clock (previously 2.5 MHz clock, but this was too fast for some HD50 cables)
    RST     : in std_logic;                           --! Firmware soft reset signal.

    DEVICE  : in std_logic;                           --! Indicates if this is the selected ODMB VME device.
    STROBE  : in std_logic;                           --! Strobe signal indicating a VME command is ready.
    COMMAND : in std_logic_vector(9 downto 0);        --! VME command signal.
    WRITER  : in std_logic;                           --! Indicates if VME command is a read or write command. Currently unused.

    INDATA  : in  std_logic_vector(15 downto 0);      --! Input data accompanying VME command.
    OUTDATA : out std_logic_vector(15 downto 0);      --! Output data to VME backplane.

    DTACK : out std_logic;                            --! Data acknowledge, indicates that VME command has been received.

    INITJTAGS : in  std_logic;                        --! Signal generated when (x)DCFEBs finish programming to invoke a reset of the JTAG state machine.
    TCK       : out std_logic_vector(NCFEB downto 1); --! JTAG test clock signal to (x)DCFEBs. One per (x)DCFEB to allow communication with a single board.
    TDI       : out std_logic;                        --! JTAG test data in signal to (x)DCFEBs.
    TMS       : out std_logic;                        --! JTAG test mode select signal to (x)DCFEBs.
    FEBTDO    : in  std_logic_vector(NCFEB downto 1); --! JTAG test data out signal from (x)DCFEBs.

    LED     : out std_logic;                          --! Debug signals.
    DIAGOUT : out std_logic_vector(17 downto 0)       --! Debug signals.
    );
end CFEBJTAG;

architecture CFEBJTAG_Arch of CFEBJTAG is
  signal logich : std_logic := '1';
  
  -- --debugging
  -- component ila_spi
  -- port (
  --   clk : in std_logic;
  --   probe0 : in std_logic_vector(511 downto 0)
  -- );
  -- end component;
  signal ila_probe : std_logic_vector(511 downto 0);
  signal prev_vme_cmd, pp_vme_cmd, ppp_vme_cmd, pppp_vme_cmd, ppppp_vme_cmd : std_logic_vector(15 downto 0);

  --Command parsing signals
  signal cmddev                                                  : std_logic_vector(15 downto 0);
  signal instshft_arb, instshft_sp                               : std_logic;
  signal datashft, instshft, readtdo, selcfeb, readcfeb, rstjtag : std_logic;
  
  --Signals for SELCFEB command
  signal ce_selfeb                                               : std_logic;
  signal selfeb                                                  : std_logic_vector(7 downto 1);
  signal d_dtack_selcfeb, dtack_selcfeb                          : std_logic;
  signal rst_init                                                : std_logic := '0';
  
  --Signals for READCFEB command
  signal d_dtack_readcfeb, dtack_readcfeb                        : std_logic;
  
  --Signals for READTDO command
  signal rdtdodk, dtack_readtdo                                  : std_logic;
  
  
  --signals for INITJTAGS and RSTJTAG command
  type reset_jtag_states is (S_RESETJTAG_IDLE, S_RESETJTAG_RESETTING, S_RESETJTAG_DTACK);
  signal reset_jtag_state : reset_jtag_states := S_RESETJTAG_IDLE;
  signal resettype                                                              : std_logic;
  --signal d1_resetjtag, q1_resetjtag, q2_resetjtag                               : std_logic;
  --signal q3_resetjtag, clr_resetjtag, resetjtag                                 : std_logic;
  signal resetjtag                                                              : std_logic;
  --signal okrst, initjtags_q, initjtags_qq, initjtags_qqq                        : std_logic;
  signal clr_resetdone, ceo_resetdone, tc_resetdone                             : std_logic;
  signal qv_resetdone                                                           : std_logic_vector(3 downto 0);
  signal resetdone, q_resetdone                                                 : std_logic;
  signal ce_resetjtag_tms, q1_resetjtag_tms, q2_resetjtag_tms                   : std_logic;
  signal q3_resetjtag_tms, q4_resetjtag_tms, q5_resetjtag_tms, q6_resetjtag_tms : std_logic;
  signal dtack_rstjtag                                                          : std_logic;
  
  --Signals for new_strobe
  signal new_strobe, new_strobe_q, new_strobe_qq             : std_logic;
  signal strobe_meta, strobe_sync : std_logic := '0';
  
  --Signals for load
  signal d1_load, d2_load, ce_load, clr_load, q_load, load      : std_logic;
  
  --Signals for busy
  signal q_busy, d_busy, clr_busy, busy, busyp1                           : std_logic;
  
  --shift DTACK signals
  signal dtack_shft, dtack_shft_d                                             : std_logic;
  signal d_dtack, ce_dtack, clr_dtack, q1_dtack, q2_dtack, q3_dtack, q4_dtack : std_logic;
  signal q5_dtack, q6_dtack                                                   : std_logic;
  
  --Signals for instruction headers
  signal ce_iheaden, clr_iheaden, iheaden                                 : std_logic;
  signal shihead                                                          : std_logic;
  signal r_doneihead, q_doneihead, ceo_doneihead, tc_doneihead, doneihead : std_logic;
  signal qv_doneihead                                                     : std_logic_vector(3 downto 0);
  signal q3_shihead_tms, q4_shihead_tms                                   : std_logic;
  signal ce_shihead_tms, q1_shihead_tms, q2_shihead_tms                   : std_logic;
  
  --signals for data headers
  signal ce_dheaden, clr_dheaden, dheaden                                 : std_logic;
  signal shdhead                                                          : std_logic;
  signal r_donedhead, q_donedhead, ceo_donedhead, tc_donedhead, donedhead : std_logic;
  signal qv_donedhead                                                     : std_logic_vector(3 downto 0);
  signal q3_shdhead_tms                                                   : std_logic;
  signal ce_shdhead_tms, q1_shdhead_tms, q2_shdhead_tms                   : std_logic;
  
  --signals for shifting data
  signal shdata                                                            : std_logic;
  signal dv_donedata, qv_donedata                                          : std_logic_vector(3 downto 0);
  signal ce_donedata, clr_donedata, up_donedata, ceo_donedata, tc_donedata : std_logic;
  signal d_donedata                                                        : std_logic;
  signal donedata                                                          : std_logic_vector(1 downto 0) := (others => '0');
  
  --signals for shifting tailers
  signal tailsp, tailsp_b                                                  : std_logic;
  signal rst_tail, rst_itail                                               : std_logic;
  signal ce_tailen, clr_tailen, clr_tailen_q, tailen                       : std_logic;
  signal shtail                                                            : std_logic;
  signal clr_donetail, q_donetail                                          : std_logic;
  signal ceo_donetail, tc_donetail, c_donetail                             : std_logic;
  signal qv_donetail                                                       : std_logic_vector(3 downto 0);
  signal donetail                                                          : std_logic;
  signal ce_shtail_tms, q1_shtail_tms, q2_shtail_tms                       : std_logic;

  --tck signals  
  signal ce_tck_global, d_tck_global, tck_global: std_logic;

  --tdi signals
  signal ce_tdi : std_logic;
  signal qv_tdi : std_logic_vector(15 downto 0);
  
  --tdo and output signals
  signal ce_shift1                                                            : std_logic;
  signal tdo                                                                  : std_logic;
  signal q_outdata                                                            : std_logic_vector(15 downto 0);

begin

  -- ila_spi_cfebjtag_i : ila_spi
  -- port map (
  --   clk => FASTCLK,
  --   probe0 => ila_probe
  -- );
  ila_probe(0) <= RST;
  ila_probe(1) <= DEVICE;
  ila_probe(2) <= STROBE;
  ila_probe(4 downto 3) <= "00";
  ila_probe(14 downto 5) <= COMMAND;
  ila_probe(18 downto 15) <= x"1";
  ila_probe(34 downto 19) <= INDATA;
  ila_probe(35) <= tck_global;
  ila_probe(36) <= q6_resetjtag_tms when (resetjtag = '1') else
                   q4_shihead_tms when (shihead = '1') else
                   q3_shdhead_tms when (shdhead = '1') else
                   (tailen and d_donedata) when (shdata = '1') else
                   q2_shtail_tms when (shtail = '1') else 'Z'; --tms
  ila_probe(37) <= qv_tdi(0);
  ila_probe(38) <= tdo;
  ila_probe(45 downto 39) <= selfeb;
  ila_probe(46) <= busy;
  ila_probe(47) <= d_dtack;
  ila_probe(48) <= dtack_shft;
  ila_probe(49) <= dtack_selcfeb or dtack_readcfeb or dtack_rstjtag or dtack_readtdo or dtack_shft;
  ila_probe(51) <= dtack_selcfeb;
  ila_probe(52) <= dtack_readcfeb;
  ila_probe(53) <= dtack_rstjtag;
  ila_probe(54) <= dtack_readtdo;
  ila_probe(55) <= load;
  ila_probe(56) <= strobe_meta;
  ila_probe(57) <= strobe_sync;
  ila_probe(73 downto 58) <= prev_vme_cmd;
  ila_probe(89 downto 74) <= pp_vme_cmd;
  ila_probe(105 downto 90) <= ppp_vme_cmd;
  ila_probe(121 downto 106) <= pppp_vme_cmd;
  ila_probe(137 downto 122) <= ppppp_vme_cmd;
  ila_probe(511 downto 138) <= (others => '0');
  
  process(SLOWCLK)
  begin
    if rising_edge(SLOWCLK) then
      if (new_strobe='1') then
        ppppp_vme_cmd <= pppp_vme_cmd;
        pppp_vme_cmd <= ppp_vme_cmd;
        ppp_vme_cmd <= pp_vme_cmd;
        pp_vme_cmd <= prev_vme_cmd;
        prev_vme_cmd <= cmddev;
      end if;
    end if;
  end process;
  
  

               
               

-- COMMAND DECODER
  cmddev <= "000" & device & command & "00";
  datashft <= '1' when (device = '1' and cmddev(7 downto 4) = x"0")  else '0';
  instshft_arb <= '1' when (device = '1' and cmddev(7 downto 4) = x"3") else '0';
  instshft_sp <= '1' when (device = '1' and cmddev(7 downto 4) = x"4") else '0';
  instshft <= '1' when (device = '1' and (cmddev(7 downto 0) = x"1C" or instshft_arb = '1' or instshft_sp = '1') ) else '0';
  readtdo  <= '1' when cmddev = x"1014" else '0';
  rstjtag  <= '1' when cmddev = x"1018" else '0';
  selcfeb  <= '1' when cmddev = x"1020" else '0';
  readcfeb <= '1' when cmddev = x"1024" else '0';




  -- Handle SELCFEB command (0x1020)
  -- Write SELFEB when SELCFEB=1 on first clock cycle after strobe. (The JTAG initialization should be broadcast)
  rst_init <= RST or INITJTAGS;
  ce_selfeb <= selcfeb and STROBE;
  FDPE_selfeb1 : FDPE port map(D => INDATA(0), C => SLOWCLK, CE => ce_selfeb, PRE => rst_init, Q => selfeb(1));
  FDPE_selfeb2 : FDPE port map(D => INDATA(1), C => SLOWCLK, CE => ce_selfeb, PRE => rst_init, Q => selfeb(2));
  FDPE_selfeb3 : FDPE port map(D => INDATA(2), C => SLOWCLK, CE => ce_selfeb, PRE => rst_init, Q => selfeb(3));
  FDPE_selfeb4 : FDPE port map(D => INDATA(3), C => SLOWCLK, CE => ce_selfeb, PRE => rst_init, Q => selfeb(4));
  FDPE_selfeb5 : FDPE port map(D => INDATA(4), C => SLOWCLK, CE => ce_selfeb, PRE => rst_init, Q => selfeb(5));
  FDPE_selfeb6 : FDPE port map(D => INDATA(5), C => SLOWCLK, CE => ce_selfeb, PRE => rst_init, Q => selfeb(6));
  FDPE_selfeb7 : FDPE port map(D => INDATA(6), C => SLOWCLK, CE => ce_selfeb, PRE => rst_init, Q => selfeb(7));

  -- Generate DTACK for SELCFEB command (0x1020) on clock cycle after strobe
  strobe_meta <= STROBE when rising_edge(SLOWCLK);
  strobe_sync <= strobe_meta when rising_edge(SLOWCLK);
  d_dtack_selcfeb <= '1' when (strobe_sync = '1' and selcfeb = '1') else '0';
  FD_selcfebdtack : FD port map(D => d_dtack_selcfeb, C => SLOWCLK, Q => dtack_selcfeb);



  -- Handle RSTJTAG command (0x1018) and INITJTAGS upon startup
  -- INITJTAGS comes from odmb_ucsb_v2 when the DCFEBs DONE bits go high - 5 clock cycle pulse
  process_nword_readback : process(SLOWCLK, RST)
  begin
  if (RST='1') then
    reset_jtag_state <= S_RESETJTAG_IDLE;
    resetjtag <= '0';
  elsif (rising_edge(SLOWCLK)) then
    case reset_jtag_state is
    
    when S_RESETJTAG_IDLE =>
      dtack_rstjtag <= '0';
      if (STROBE='1' and rstjtag='1') then
        reset_jtag_state <= S_RESETJTAG_RESETTING;
        resetjtag <= '1';
        resettype <= '0';
      elsif (INITJTAGS='1') then
        reset_jtag_state <= S_RESETJTAG_RESETTING;   
        resetjtag <= '1';  
        resettype <= '1';   
      else
        reset_jtag_state <= S_RESETJTAG_IDLE;
        resetjtag <= '0';
        resettype <= '0';
      end if;
      
    when S_RESETJTAG_RESETTING => 
      --wait until reset is finished to issue DTACK
      dtack_rstjtag <= '0';
      if (resetdone = '1') then
        if (resettype = '1') then
          reset_jtag_state <= S_RESETJTAG_IDLE;
        else
          reset_jtag_state <= S_RESETJTAG_DTACK;
        end if;
        resetjtag <= '0';
      else
        reset_jtag_state <= S_RESETJTAG_RESETTING;   
        resetjtag <= '1';        
      end if;
      
    when S_RESETJTAG_DTACK => 
      --hold DTACK until STROBE goes low
      dtack_rstjtag <= '1';
      resetjtag <= '0';    
      if (STROBE='1') then
        reset_jtag_state <= S_RESETJTAG_DTACK;
      else
        reset_jtag_state <= S_RESETJTAG_IDLE;
      end if;
      
    when others =>
      dtack_rstjtag <= '0';
      reset_jtag_state <= S_RESETJTAG_IDLE;
      resetjtag <= '0';
    end case;
  end if;
  end process;

  -- Generate RESETDONE 
  -- PULSE2SLOW only works if the signal is 1 CC long in the original clock domain
  -- Generate resetdone, reset to 0 on load and cycle after done, goes high 0b1100=12 cycles after resetjtag enabled
  -- resetjtag_PULSE  : PULSE2FAST port map(DOUT => clr_resetjtag_pulse, CLK_DOUT => FASTCLK, RST => '0', DIN => clr_resetjtag);
  -- resetdone_PULSE  : PULSE2SLOW port map(DOUT => clr_resetdone, CLK_DOUT => SLOWCLK, CLK_DIN => FASTCLK, RST => '0', DIN => clr_resetjtag_pulse);
  clr_resetdone <= '1' when (q_resetdone = '1' or RST = '1')                        else '0';
  CB4CE(SLOWCLK, resetjtag, clr_resetdone, qv_resetdone, qv_resetdone, ceo_resetdone, tc_resetdone); --(C, CE, CLR, Q_in, Q, CEO, TC)
  resetdone     <= '1' when (qv_resetdone = "1011") else '0'; --12 - 1 clock cycles since resetjtag doesn't go low until the next one
  FD_qresetdone : FD port map(D => resetdone, C => SLOWCLK, Q => q_resetdone);

  -- Generate TMS when resetjtag=1; pattern is 111110 (recall TCK is half the frequency of SLOWCLK so ce_shihead_tms is only enabled every other SLOWLCK cycle)
  ce_resetjtag_tms <= (resetjtag and tck_global);
  FDCE_q1resetjtagtms : FDCE port map(D => q6_resetjtag_tms, C => SLOWCLK, CE => ce_resetjtag_tms, CLR => RST, Q => q1_resetjtag_tms);
  FDPE_q2resetjtagtms : FDPE port map(D => q1_resetjtag_tms, C => SLOWCLK, CE => ce_resetjtag_tms, PRE => RST, Q => q2_resetjtag_tms);
  FPDE_q3resetjtagtms : FDPE port map(D => q2_resetjtag_tms, C => SLOWCLK, CE => ce_resetjtag_tms, PRE => RST, Q => q3_resetjtag_tms);
  FDPE_q4resetjtagtms : FDPE port map(D => q3_resetjtag_tms, C => SLOWCLK, CE => ce_resetjtag_tms, PRE => RST, Q => q4_resetjtag_tms);
  FDPE_q5resetjtagtms : FDPE port map(D => q4_resetjtag_tms, C => SLOWCLK, CE => ce_resetjtag_tms, PRE => RST, Q => q5_resetjtag_tms);
  FDPE_q6resetjtagtms : FDPE port map(D => q5_resetjtag_tms, C => SLOWCLK, CE => ce_resetjtag_tms, PRE => RST, Q => q6_resetjtag_tms);





  
  -- General signals for SHFT commands: new_strobe, load, busy, dtack

  -- Generate new_strobe, which is 1 only on the first SLOWCLK edge after a new strobe
  FDCE_new_strobe_q : FDCE port map (D => STROBE, C => SLOWCLK, CE => '1', CLR => RST, Q => new_strobe_q);
  FDCE_new_strobe_qq : FDCE port map (D => new_strobe_q, C => SLOWCLK, CE => '1', CLR => RST, Q => new_strobe_qq);
  new_strobe <= new_strobe_q and (not new_strobe_qq);

  -- Generate load on third SLOWCLK edge after new STROBE for DATASHFT and INSTSHFT commands IF not already busy with a JTAG command  
  d1_load  <= datashft or instshft;
  clr_load <= load or RST;
  FDCE_qload : FDCE port map(D => d1_load, C => SLOWCLK, CE => new_strobe, CLR => clr_load, Q => q_load);
  d2_load  <= '1' when (q_load = '1' and busy = '0') else '0';
  FDC_load : FDC port map(D => d2_load, C => SLOWCLK, CLR => RST, Q => load);
  
  --note VME timeout at 1023 40MHz clock cycles
  --load <= (datashft or instshft) and new_strobe;

  -- Generate busy on fifth SLOWCLK edge after STROBE, persist until all data or tailer sent
  -- once busy='1' every clock cycle TCK switches (i.e. TCK goes high on third clock cycle after load)
  FDC_qbusy : FDC port map(D => load, C => SLOWCLK, CLR => RST, Q => q_busy);
  clr_busy <= '1' when ((donedata(1) = '1' and (tailen = '0')) or rst = '1' or donetail = '1') else '0';
  d_busy   <= '1' when (q_busy = '1' or busy = '1')                                            else '0';
  --d_busy   <= load or busy;
  FDC_busy : FDC port map(D => d_busy, C => SLOWCLK, CLR => clr_busy, Q => busy);
  FDC_busyp1 : FDC port map(D => busy, C => SLOWCLK, CLR => RST, Q => busyp1);
  
  -- Generate dtack for DATASHFT and INSTSHFT commands, at least 4 cycles after strobe when busy goes low
  d_dtack   <= (datashft or instshft);
  ce_dtack  <= not busy;
  clr_dtack <= not STROBE;
  FDCE_q1dtack : FDCE port map(D => d_dtack, C => SLOWCLK, CE => CE_dtack, CLR => CLR_dtack, Q => q1_dtack);
  FDC_q2dtack : FDC port map(D => q1_dtack, C => SLOWCLK, CLR => CLR_dtack, Q => q2_dtack);
  FD_q3dtack : FD port map(D => q2_dtack, C => SLOWCLK, Q => q3_dtack);
  FD_q4dtack : FD port map(D => q3_dtack, C => SLOWCLK, Q => q4_dtack);
  dtack_shft_d <= (q1_dtack and q2_dtack and q3_dtack and q4_dtack); --enough time for everything to latch
  dtack_shft <= dtack_shft_d when rising_edge(SLOWCLK);


   
  
  -- Handle shifting instruction header for relevant commands (0x1Y1C 0x1Y34 0x1Y3C 0x1Y4C)
  
  -- Generate iheaden on first clock cycle after STROBE, shihead when busy is high
  ce_iheaden <= '1' when (STROBE = '1' and busy = '0' and instshft = '1') else '0';
  clr_iheaden <= '1' when (RST = '1' or doneihead = '1') else '0';
  FDCE_iheaden : FDCE port map(D => COMMAND(0), C => SLOWCLK, CE => ce_iheaden, CLR => clr_iheaden, Q => iheaden);
  shihead <= '1' when (busy = '1' and iheaden = '1') else '0';

  -- Generate doneihead, reset to 0 on load and cycle after done, goes high 0b1000=8 cycles after BUSY enabled
  r_doneihead <= '1' when (LOAD = '1' or RST = '1' or q_doneihead = '1')        else '0';
  CB4RE(SLOWCLK, shihead, r_doneihead, qv_doneihead, qv_doneihead, ceo_doneihead, tc_doneihead); --(C, CE, CLR, Q_in, Q, CEO, TC)
  doneihead   <= '1' when (qv_doneihead = "1000") else '0';
  FD_qdoneihead : FD port map(D => doneihead, C => SLOWCLK, Q => q_doneihead);

  -- Generate TMS when shihead=1; pattern is 1100 (recall TCK is half the frequency of SLOWCLK so ce_shihead_tms is only enabled every other SLOWLCK cycle)
  ce_shihead_tms <= '1'            when ((shihead = '1') and (TCK_GLOBAL = '1')) else '0';
  FDCE_q1shiheadtms : FDCE port map(D => q4_shihead_tms, C => SLOWCLK, CE => ce_shihead_tms, CLR => RST, Q => q1_shihead_tms); --4th bit sent
  FDCE_q2shiheadtms : FDCE port map(D => q1_shihead_tms, C => SLOWCLK, CE => ce_shihead_tms, CLR => RST, Q => q2_shihead_tms); --3rd bit sent
  FDPE_q3shiheadtms : FDPE port map(D => q2_shihead_tms, C => SLOWCLK, CE => ce_shihead_tms, PRE => RST, Q => q3_shihead_tms); --2nd bit sent
  FDPE_q4shiheadtms : FDPE port map(D => q3_shihead_tms, C => SLOWCLK, CE => ce_shihead_tms, PRE => RST, Q => q4_shihead_tms); --1st bit sent
  
  
  
  
  -- Handle shifting data header for relevant commands (0x1Y0C 0x1Y04)
  
  -- Generate dheaden on first clock cycle after STROBE, shdhead when busy is high
  ce_dheaden  <= '1' when (STROBE = '1' and BUSY = '0' and datashft='1') else '0';
  clr_dheaden <= '1' when (RST = '1' or donedhead = '1') else '0';
  FDCE_dheaden : FDCE port map(D => COMMAND(0), C => SLOWCLK, CE => ce_dheaden, CLR => clr_dheaden, Q => dheaden);
  shdhead <= '1' when (BUSY = '1' and dheaden = '1') else '0';
  
  -- Generate donedhead, reset to 0 on load and cycle after done, goes high 0b0110=6 cycles after BUSY enabled
  r_donedhead <= '1' when (LOAD = '1' or RST = '1' or q_donedhead = '1')       else '0';
  CB4RE(SLOWCLK, shdhead, r_donedhead, qv_donedhead, qv_donedhead, CEO_donedhead, TC_donedhead); --(C, CE, CLR, Q_in, Q, CEO, TC)
  donedhead   <= '1' when (qv_donedhead = "0110") else '0';
  FD_qdonedhead : FD port map(D => donedhead, C => SLOWCLK, Q => q_donedhead);

  -- Generate tms when shdhead=1; pattern is 100 (recall TCK is half the frequency of SLOWCLK so ce_shdhead_tms is only enabled every other SLOWLCK cycle)
  ce_shdhead_tms <= '1' when ((shdhead = '1') and (tck_global = '1') ) else '0';
  FDCE_q1shdheadtms : FDCE port map(D => q3_shdhead_tms, C => SLOWCLK, CE => ce_shdhead_tms, CLR => RST, Q => q1_shdhead_tms); --3rd bit sent
  FDCE_q2shdheadtms : FDCE port map(D => q1_shdhead_tms, C => SLOWCLK, CE => ce_shdhead_tms, CLR => RST, Q => q2_shdhead_tms); --2nd bit sent
  FDPE_q3shdheadtms : FDPE port map(D => q2_shdhead_tms, C => SLOWCLK, CE => ce_shdhead_tms, PRE => RST, Q => q3_shdhead_tms); --1st bit sent

  
  
  
  -- Handle shifting data for all INSTSHFT and DATASHFT commands
  
  -- Assert shdata when busy, not shifting headers, and not yet done shifting data
  shdata  <= '1' when (busy = '1' and dheaden = '0' and iheaden = '0' and donedata(1) = '0') else '0';

  -- Generate DONEDATA using counter, d_donedata is asserted COMMAND(9 downto 6)*2 cycles after shdata is first asserted, donedata(0) and (1) are asserted on the
  -- next two clock edges in order
  dv_donedata  <= COMMAND(9 downto 6);
  ce_donedata  <= '1' when (shdata = '1' and tck_global = '1')                       else '0';
  clr_donedata <= '1' when (RST = '1' or donedata(1) = '1' or donedata(0) = '1') else '0';
  up_donedata  <= '0';                  -- connected to GND = always count down
  CB4CLED(SLOWCLK, ce_donedata, clr_donedata, load, up_donedata, dv_donedata, qv_donedata, qv_donedata, ceo_donedata, tc_donedata);  -- (C, CE, CLR, L, UP, D, Q_in, Q, CEO, TC)
  d_donedata   <= '1' when (qv_donedata = "0000" and load = '0')                 else '0';
  FDCE_donedata0 : FDCE port map(D => d_donedata, C => SLOWCLK, CE => shdata, CLR => load, Q => donedata(0));
  FDC_donedata1 : FDC port map(D => donedata(0), C => SLOWCLK, CLR => load, Q => donedata(1));
  
  

  
  -- Handle shifting TMS tailer for relevant INSTSHFT and DATASHFT commands (0x1Y08 0x1Y0C 0x1Y1C 0x1Y38 0x1Y3C 0x1Y48 0x1Y4C)

  -- Generate tailen cycle after load, shtail when busy is asserted and donedata(1)
  ce_tailen  <= '1' when (load = '1' and (instshft = '1' or datashft = '1')) else '0';
  clr_tailen <= '1' when (RST = '1' or donetail = '1')      else '0';
  FD_clrtailenq : FD port map(D => clr_tailen, C => SLOWCLK, Q => clr_tailen_q);
  FDCE_tailen : FDCE port map(D => command(1), C => SLOWCLK, CE => ce_tailen, CLR => clr_tailen, Q => tailen);
  shtail <= '1' when (busy = '1' and donedata(1) = '1' and tailen = '1') else '0';

  -- Handle signals for special tailer - 
  FDCE_tailsp : FDCE port map(D => instshft_sp, C => SLOWCLK, CE => ce_tailen, CLR => rst_itail, Q => tailsp);
  tailsp_b <= not tailsp;
  SET_ITAIL_RST : PULSE2SAME port map(DOUT => rst_itail, CLK_DOUT => slowclk, RST => rst, DIN => tailsp_b);

  -- Generate donetail, reset to 0 on load and cycle after done, goes high 2 cycles after shtail enabled for special tailer and 4 otherwise
  clr_donetail <= '1' when (RST = '1' or q_donetail = '1') else '0';
  CB4CE(SLOWCLK, shtail, clr_donetail, qv_donetail, qv_donetail, ceo_donetail, tc_donetail); --(C, CE, CLR, Q_in, Q, CEO, TC)
  donetail     <= '1' when ((qv_donetail="0010" and tailsp='1') or (qv_donetail="0100" and tailsp='0')) else '0';
  FD_1_qdonetail : FD_1 port map(D => donetail, C => SLOWCLK, Q => q_donetail);

  -- Generate tms when shtail=1; pattern is 10 (recall TCK is half the frequency of SLOWCLK so ce_shdhead_tms is only enabled every other SLOWLCK cycle)
  ce_shtail_tms <= '1'           when ((shtail = '1') and (tck_global = '1')) else '0';
  rst_tail <=  rst or rst_itail;
  FDCE_q1shtailtms : FDCE port map(D => q2_shtail_tms, C => SLOWCLK, CE => ce_shtail_tms, CLR => rst_tail, Q => q1_shtail_tms);
  FDPE_q2shtailtms : FDPE port map(D => q1_shtail_tms, C => SLOWCLK, CE => ce_shtail_tms, PRE => rst_tail, Q => q2_shtail_tms);




  -- Handle central JTAG signals (TCK, TDI, TMS, TDO)

  -- Multiplex TMS's together
  TMS       <= q6_resetjtag_tms when (resetjtag = '1') else
               q4_shihead_tms when (shihead = '1') else
               q3_shdhead_tms when (shdhead = '1') else
               (tailen and d_donedata) when (shdata = '1') else
               q2_shtail_tms when (shtail = '1') else 'Z';
  --TMS <= tms_inner;

  -- Generate tck_global
  ce_tck_global <= '1' when (resetjtag = '1' or busy = '1') else '0';
  d_tck_global  <= not tck_global;
  FDCE_tckglobal : FDCE port map(D => d_tck_global, C => SLOWCLK, CE => ce_tck_global, CLR => RST, Q => tck_global);

  -- Generate individual TCKs
  TCK(1) <= tck_global when selfeb(1)='1' else '0';
  TCK(2) <= tck_global when selfeb(2)='1' else '0';
  TCK(3) <= tck_global when selfeb(3)='1' else '0';
  TCK(4) <= tck_global when selfeb(4)='1' else '0';
  TCK(5) <= tck_global when selfeb(5)='1' else '0';
  TCK(6) <= tck_global when selfeb(6)='1' else '0';
  TCK(7) <= tck_global when selfeb(7)='1' else '0';

  -- Generate TDI
  TDI <= qv_tdi(0);
  ce_tdi <= (shdata and tck_global);
  SR16CLRE(SLOWCLK, ce_tdi, RST, load, qv_tdi(0), INDATA, qv_tdi, qv_tdi);

  -- Generate TDO and shift into OUTDATA
  tdo <= FEBTDO(1) when SELFEB = "0000001" else
         FEBTDO(2) when SELFEB = "0000010" else
         FEBTDO(3) when SELFEB = "0000100" else
         FEBTDO(4) when SELFEB = "0001000" else
         FEBTDO(5) when SELFEB = "0010000" else
         FEBTDO(6) when SELFEB = "0100000" else
         FEBTDO(7) when SELFEB = "1000000" else '0';
  ce_shift1            <= shdata and not tck_global;
  SR16LCE(SLOWCLK, ce_shift1, RST, tdo, q_outdata, q_outdata);




  -- Handle OUTDATA (includes  READCFEB command (0x1024), read TDO command (0x1014))
  rdtdodk <= '1' when (STROBE = '1' and readtdo = '1' and busyp1 = '0' and busy = '0') else '0';
  OUTDATA <= "000000000" & selfeb(7 downto 1) when (STROBE = '1' and readcfeb = '1') else
             q_outdata(15 downto 0) when (rdtdodk = '1') else (others => 'Z');


  -- Generate DTACK when READCFEB=1 on second clock cycle after strobe (see combined DTACK logic)
  d_dtack_readcfeb <= '1' when (strobe_sync = '1' and readcfeb = '1') else '0';
  FD_readcfebdtack : FD port map(D => d_dtack_readcfeb, C => SLOWCLK, Q => dtack_readcfeb);
  
  --Generate DTACK on cycle after rdtdodk
  FD_readtdodtack : FD port map(D => rdtdodk, C => SLOWCLK, Q => dtack_readtdo);


  -- Handle DTACK
  DTACK <= '1' when (dtack_selcfeb = '1') or
                 (dtack_readcfeb = '1') or
                 (dtack_rstjtag = '1') or
                 (dtack_readtdo = '1') or
                 (dtack_shft = '1') else '0';




  --debugging stuff

  -- Generate LED.
  LED <= CE_SHIHEAD_TMS;  

  -- generate DIAGOUT
  DIAGOUT(6 downto 0)  <= selfeb(7 downto 1);
  DIAGOUT(7) <= RST;
  DIAGOUT(8) <= INITJTAGS;
  DIAGOUT(9) <= readcfeb;
  DIAGOUT(10) <= selcfeb;
  DIAGOUT(11) <= shihead;
  DIAGOUT(12) <= shdhead;
  DIAGOUT(13) <= shdata;
  DIAGOUT(14) <= shtail;
  DIAGOUT(15) <= dtack_readcfeb;
  DIAGOUT(16) <= dtack_readtdo;
  DIAGOUT(17) <= STROBE;

end CFEBJTAG_Arch;
