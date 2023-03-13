library ieee;
library work;
library UNISIM;
use ieee.std_logic_1164.all;
use work.Latches_Flipflops.all;
use work.ucsb_types.all;
use UNISIM.vcomponents.all;

--! @brief module that can send JTAG signals to/from ODMB FPGA
--! @details Supported VME commands:
--! * W 2Y00 shift Y+1 data bits with no JTAG header or tailer
--! * W 2Y04 shift Y+1 data bits with JTAG header 
--! * W 2Y08 shift Y+1 data bits with JTAG tailer
--! * W 2Y0C shift Y+1 data bits with JTAG header and tailer
--! * R 2014 read last data bits shifted into TDO register
--! * W 2018 send JTAG reset pattern
--! * W 2Y1C shift Y+1 instruction bits with JTAG header and tailer
--! * W 2020 Set default polarity of JTAG select (should not use for ODMB7)
entity ODMBJTAG is

  port (

    FASTCLK : in std_logic;                      --! 40 MHz clock. Unused.
    SLOWCLK : in std_logic;                      --! 2.5 MHz clock.
    RST     : in std_logic;                      --! Soft reset.
                                                
    DEVICE  : in std_logic;                      --! Indicates if this is the selected VME device.
    STROBE  : in std_logic;                      --! Indicates a command is ready to execute.
    COMMAND : in std_logic_vector(9 downto 0);   --! VME command to execute.
    WRITER  : in std_logic;                      --! Indicates if command is read (1) or write (0).

    INDATA  : in  std_logic_vector(15 downto 0); --! Input VME data from backplane.
    OUTDATA : out std_logic_vector(15 downto 0); --! Output VME data to backplane.

    DTACK : out std_logic;                       --! VME data acknowledge to backplane.

    INITJTAGS : in  std_logic;                   --! Signal to automatically send JTAG reset. Unconnected.
    TCK       : out std_logic;                   --! TCK signal to Kintex Ultrascale FPGA
    TDI       : out std_logic;                   --! TDI signal to Kintex Ultrascale FPGA
    TMS       : out std_logic;                   --! TMS signal to Kintex Ultrascale FPGA
    ODMBTDO   : in  std_logic;                   --! TDO signal from Kintex Ultrascale FPGA

    JTAGSEL : out std_logic;                     --! Signal to multiplex JTAG signals. 1 selects external connection/discrete logic while 0 selects firmware (this).
    LED : out std_logic                          --! Debug signals.
    );

end ODMBJTAG;

architecture ODMBJTAG_Arch of ODMBJTAG is

  --Declaring internal signals

  -- component ila_odmbJTAG is
  --     port (
  --         clk : in std_logic := '0';
  --         probe0 : in std_logic_vector(15 downto 0) := (others=> '0');
  --         probe1 : in std_logic_vector(15 downto 0) := (others=> '0');
  --         probe2 : in std_logic_vector(15 downto 0) := (others=> '0');
  --         probe3 : in std_logic_vector(14 downto 0) := (others=> '0');
  --         probe4 : in std_logic_vector(4 downto 0) := (others=> '0')
  --     );
  -- end component;

  constant logich : std_logic := '1';
  -- signal trigger  : std_logic_vector(14 downto 0) := (others=> '0');
  -- signal data  : std_logic_vector(4 downto 0) := (others=> '0');

  signal cmddev                                                            : std_logic_vector(15 downto 0);
  signal datashft, instshft, readtdo, rstjtag                              : std_logic;
  signal w_polarity                                                        : std_logic;

  signal d1_resetjtag, q1_resetjtag, q2_resetjtag                          : std_logic;
  signal q3_resetjtag, clr_resetjtag, resetjtag                            : std_logic;
  signal okrst, initjtags_q, initjtags_qq, initjtags_qqq                   : std_logic;
  signal dtack_rstjtag                                                     : std_logic;

  signal ce_resetjtag_tms, q1_resetjtag_tms, q2_resetjtag_tms              : std_logic;
  signal q3_resetjtag_tms, q4_resetjtag_tms                                : std_logic;
  signal q5_resetjtag_tms, q6_resetjtag_tms                                : std_logic;
  signal clr_resetdone, ceo_resetdone, tc_resetdone                        : std_logic;
  signal qv_resetdone                                                      : std_logic_vector(3 downto 0);
  signal q_resetdone, resetdone                                            : std_logic;

  signal d1_load, d2_load, clr_load, q_load, load                          : std_logic;
  signal q_busy, d_busy, clr_busy, busy, busyp1                            : std_logic;
  signal d_dtack, ce_dtack, clr_dtack                                      : std_logic;
  signal q1_dtack, q2_dtack, q3_dtack, q4_dtack                            : std_logic;
  signal dtack_shft_pre, dtack_shft, dtack_ila                             : std_logic;

  signal ce_iheaden, clr_iheaden, iheaden, shihead                         : std_logic;
  signal r_doneihead, q_doneihead, ceo_doneihead, tc_doneihead, doneihead  : std_logic;
  signal qv_doneihead                                                      : std_logic_vector(3 downto 0);
  signal ce_shihead_tms, q1_shihead_tms, q2_shihead_tms                    : std_logic;
  signal q3_shihead_tms, q4_shihead_tms                                    : std_logic;

  signal ce_dheaden, clr_dheaden, dheaden, shdhead                         : std_logic;
  signal r_donedhead, q_donedhead, ceo_donedhead, tc_donedhead, donedhead  : std_logic;
  signal qv_donedhead                                                      : std_logic_vector(3 downto 0);
  signal ce_shdhead_tms, q1_shdhead_tms, q2_shdhead_tms, q3_shdhead_tms    : std_logic;

  signal ce_donedata, clr_donedata, up_donedata, ceo_donedata, tc_donedata : std_logic;
  signal shdata                                                            : std_logic;
  signal dv_donedata, qv_donedata                                          : std_logic_vector(3 downto 0);
  signal d_donedata                                                        : std_logic;
  signal donedata                                                          : std_logic_vector(1 downto 0);

  signal ce_tailen, clr_tailen, tailen                                     : std_logic;
  signal qv_donetail                                                       : std_logic_vector(3 downto 0);
  signal ceo_donetail, tc_donetail                                         : std_logic;
  signal shtail                                                            : std_logic;
  signal clr_donetail, q_donetail                                          : std_logic;
  signal donetail                                                          : std_logic;
  signal ce_shtail_tms, q1_shtail_tms, q2_shtail_tms                       : std_logic;

  signal tck_global, ce_tck_global, d_tck_global                           : std_logic;
  signal rst_b, rst_pulse, rst_pulse_b, pol_pulse                          : std_logic;
  signal default_low, default_high                                         : std_logic := '1';
  signal jtagsel_inner, jtagsel_in                                         : std_logic;
  signal dd_dtack_pol, d_dtack_pol, dtack_pol                              : std_logic := '0';

  signal ce_tdi, tdi_global, tdo_global, tms_global                        : std_logic;
  signal qv_tdi                                                            : std_logic_vector(15 downto 0);
  signal rdtdodk, dtack_readtdo                                            : std_logic;
  signal shft_en                                                           : std_logic;
  signal q_outdata                                                         : std_logic_vector(15 downto 0);

begin

  -- COMMAND DECODER
  cmddev <= "000" & DEVICE & COMMAND & "00";
  datashft <= '1' when (DEVICE = '1' and cmddev(7 downto 4) = x"0")  else '0';
  instshft <= '1' when (DEVICE = '1' and cmddev(7 downto 0) = x"1C") else '0';
  readtdo  <= '1' when cmddev = x"1014" else '0';
  rstjtag  <= '1' when cmddev = x"1018" else '0';
  w_polarity <= '1' when (cmddev = x"1020" and WRITER = '0' and STROBE = '1') else '0';




  -- Handle RSTJTAG COMMAND (0x1018) and INITJTAGS upon startup
  -- resetjtag set 4th clock cycle after INITJTAGS or STROBE
  -- INITJTAGS comes from odmb_ucsb_v2 when the DCFEBs DONE bits go high
  d1_resetjtag  <= '1' when ((STROBE = '1' and rstjtag = '1') or INITJTAGS = '1') else '0';
  FDC_Q1RESETJTAG : FDC port map(D => d1_resetjtag, C => SLOWCLK, CLR => RST, Q => q1_resetjtag);
  FDC_Q2RESETJTAG : FDC port map(D => q1_resetjtag, C => SLOWCLK, CLR => RST, Q => q2_resetjtag);
  okrst         <= '1' when (q1_resetjtag = '1' and q2_resetjtag = '1')           else '0';
  FDC_Q3RESETJTAG : FDCE port map(D => logich, C => SLOWCLK, CE => okrst, CLR => clr_resetjtag, Q => q3_resetjtag);
  FDC_RESETJTAG : FDC port map(D => q3_resetjtag, C => SLOWCLK, CLR => clr_resetjtag, Q => resetjtag);

  -- Generate RESETDONE
  -- PULSE2SLOW only works if the signal is 1 CC long in the original clock domain
  -- Generate resetdone, reset to 0 on load and cycle after done, goes high 0b1100=12 cycles after resetjtag enabled
  clr_resetdone <= '1' when (q_resetdone = '1' or RST = '1')                        else '0';
  CB4CE(SLOWCLK, resetjtag, clr_resetdone, qv_resetdone, qv_resetdone, ceo_resetdone, tc_resetdone); --(C, CE, CLR, Q_in, Q, CEO, TC)
  resetdone     <= '1' when (qv_resetdone = "1100") else '0';
  clr_resetjtag <= (resetdone or RST);
  FD_QRESETDONE : FD port map(D => resetdone, C => SLOWCLK, Q => q_resetdone);

  -- Generate TMS when resetjtag=1; pattern is 111110 (recall TCK is half the frequency of SLOWCLK so ce_shihead_tms is only enabled every other SLOWLCK cycle)
  ce_resetjtag_tms <= (resetjtag and tck_global);
  FDCE_Q1RESETJTAGTMS : FDCE port map(D => q6_resetjtag_tms, C => SLOWCLK, CE => ce_resetjtag_tms, CLR => RST, Q => q1_resetjtag_tms);
  FDCE_Q2RESETJTAGTMS : FDPE port map(D => q1_resetjtag_tms, C => SLOWCLK, CE => ce_resetjtag_tms, PRE => RST, Q => q2_resetjtag_tms);
  FDCE_Q3RESETJTAGTMS : FDPE port map(D => q2_resetjtag_tms, C => SLOWCLK, CE => ce_resetjtag_tms, PRE => RST, Q => q3_resetjtag_tms);
  FDCE_Q4RESETJTAGTMS : FDPE port map(D => q3_resetjtag_tms, C => SLOWCLK, CE => ce_resetjtag_tms, PRE => RST, Q => q4_resetjtag_tms);
  FDCE_Q5RESETJTAGTMS : FDPE port map(D => q4_resetjtag_tms, C => SLOWCLK, CE => ce_resetjtag_tms, PRE => RST, Q => q5_resetjtag_tms);
  FDCE_Q6RESETJTAGTMS : FDPE port map(D => q5_resetjtag_tms, C => SLOWCLK, CE => ce_resetjtag_tms, PRE => RST, Q => q6_resetjtag_tms);

  -- Generate dtack for RSTJTAG COMMAND
  FDC_INITJTAGSQ : FDC port map(D => INITJTAGS, C => SLOWCLK, CLR => RST, Q => initjtags_q);
  FDC_INITJTAGSQQ : FDC port map(D => initjtags_q, C => SLOWCLK, CLR => RST, Q => initjtags_qq);
  FDC_INITJTAGSQQQ : FDC port map(D => initjtags_qq, C => SLOWCLK, CLR => RST, Q => initjtags_qqq);
  dtack_rstjtag <= resetjtag and (not initjtags_qqq);




  -- General signals for SHFT commands: load, busy, dtack

  -- Generate load on third clock cycle after STROBE for DATASHFT and INSTSHFT commands IF not already busy with a JTAG COMMAND
  d1_load  <= datashft or instshft;
  clr_load <= load or RST;
  FDCE_QLOAD : FDCE port map(D => d1_load, C => SLOWCLK, CE => STROBE, CLR => clr_load, Q => q_load);
  d2_load  <= '1' when (q_load = '1' and busy = '0') else '0';
  FDC_LOAD : FDC port map(D => d2_load, C => SLOWCLK, CLR => RST, Q => load);

  -- Generate busy on second clock cycle after load (fourth after new STROBE), persist until all data or tailer sent
  -- once busy='1' every clock cycle TCK switches (i.e. TCK goes high on third clock cycle after load)
  FDC_QBUSY : FDC port map(D => load, C => SLOWCLK, CLR => RST, Q => q_busy);
  clr_busy <= '1' when ((donedata(1) = '1' and (tailen = '0')) or RST = '1' or donetail = '1') else '0';
  d_busy   <= '1' when (q_busy = '1' or busy = '1')                                            else '0';
  FDC_BUSY : FDC port map(D => d_busy, C => SLOWCLK, CLR => clr_busy, Q => busy);
  FDC_BUSYP1 : FDC port map(D => busy, C => SLOWCLK, CLR => RST, Q => busyp1);

  -- Generate DTACK when datashft=1 or instshft=1
  d_dtack   <= (datashft or instshft);
  ce_dtack  <= not busy;
  clr_dtack <= not STROBE;
  FDCE_Q1DTACK  : FDCE port map (D => d_dtack, C => SLOWCLK, CE => ce_dtack, CLR => clr_dtack, Q => q1_dtack);
  FDC_Q2DTACK : FDC port map(D => q1_dtack, C => SLOWCLK, CLR => clr_dtack, Q => q2_dtack);
  FD_Q3DTACK : FD port map(D => q2_dtack, C => SLOWCLK, Q => q3_dtack);
  -- FD_Q4DTACK : FD port map(D => q3_dtack, C => SLOWCLK, Q => q4_dtack);
  dtack_shft <= '1' when (q2_dtack = '1' and q3_dtack = '1') else '0';
  -- FD_DTACK : FD port map(D => dtack_shft_pre, C => SLOWCLK, Q => dtack_shft);



  -- Handle shifting instruction header for relevant commands (0x2Y1C)

  -- Generate iheaden on first clock cycle after STROBE, shihead when busy is high
  ce_iheaden <= '1' when (STROBE = '1' and busy = '0' and instshft = '1') else '0';
  clr_iheaden <= '1' when (RST = '1' or doneihead = '1') else '0';
  FDCE_IHEADEN : FDCE port map(D => COMMAND(0), C => SLOWCLK, CE => ce_iheaden, CLR => clr_iheaden, Q => iheaden);
  shihead <= '1' when (busy = '1' and iheaden = '1') else '0';

  -- Generate doneihead, reset to 0 on load and cycle after done, goes high 0b1000=8 cycles after BUSY enabled
  r_doneihead <= '1' when (load = '1' or RST = '1' or q_doneihead = '1') else '0';
  CB4RE(SLOWCLK, shihead, r_doneihead, qv_doneihead, qv_doneihead, ceo_doneihead, tc_doneihead); --(C, CE, CLR, Q_in, Q, CEO, TC)
  doneihead   <= '1' when (qv_doneihead = "1000") else '0';
  FD_QDONEIHEAD : FD port map(D => doneihead, C => SLOWCLK, Q => q_doneihead);

  -- Generate TMS when shihead=1; pattern is 1100 (recall TCK is half the frequency of SLOWCLK so ce_shihead_tms is only enabled every other SLOWLCK cycle)
  ce_shihead_tms <= '1'            when ((shihead = '1') and (TCK_GLOBAL = '1')) else '0';
  FDCE_Q1SHIHEADTMS : FDCE port map(D => q4_shihead_tms, C => SLOWCLK, CE => ce_shihead_tms, CLR => RST, Q => q1_shihead_tms); --4th bit sent
  FDCE_Q2SHIHEADTMS : FDCE port map(D => q1_shihead_tms, C => SLOWCLK, CE => ce_shihead_tms, CLR => RST, Q => q2_shihead_tms); --3rd bit sent
  FDPE_Q3SHIHEADTMS : FDPE port map(D => q2_shihead_tms, C => SLOWCLK, CE => ce_shihead_tms, PRE => RST, Q => q3_shihead_tms); --2nd bit sent
  FDPE_Q4SHIHEADTMS : FDPE port map(D => q3_shihead_tms, C => SLOWCLK, CE => ce_shihead_tms, PRE => RST, Q => q4_shihead_tms); --1st bit sent




  -- Handle shifting data header for relevant commands (0x2Y0C 0x2Y04)

  -- Generate dheaden on first clock cycle after STROBE, shdhead when busy is high
  ce_dheaden  <= '1' when (STROBE = '1' and BUSY = '0' and datashft='1') else '0';
  clr_dheaden <= '1' when (RST = '1' or donedhead = '1') else '0';
  FDCE_DHEADEN : FDCE port map(D => COMMAND(0), C => SLOWCLK, CE => ce_dheaden, CLR => clr_dheaden, Q => dheaden);
  shdhead <= '1' when (BUSY = '1' and dheaden = '1') else '0';

  -- Generate donedhead, reset to 0 on load and cycle after done, goes high 0b0110=6 cycles after BUSY enabled
  r_donedhead <= '1' when (load = '1' or RST = '1' or q_donedhead = '1')       else '0';
  CB4RE(SLOWCLK, shdhead, r_donedhead, qv_donedhead, qv_donedhead, ceo_donedhead, tc_donedhead); --(C, CE, CLR, Q_in, Q, CEO, TC)
  donedhead   <= '1' when (qv_donedhead = "0110") else '0';
  FD_QDONEDHEAD : FD port map(D => donedhead, C => SLOWCLK, Q => q_donedhead);

  -- Generate tms when shdhead=1; pattern is 100 (recall TCK is half the frequency of SLOWCLK so ce_shdhead_tms is only enabled every other SLOWLCK cycle)
  ce_shdhead_tms <= '1' when ((shdhead = '1') and (tck_global = '1') ) else '0';
  FDCE_Q1SHDHEADTMS : FDCE port map(D => q3_shdhead_tms, C => SLOWCLK, CE => ce_shdhead_tms, CLR => RST, Q => q1_shdhead_tms); --3rd bit sent
  FDCE_Q2SHDHEADTMS : FDCE port map(D => q1_shdhead_tms, C => SLOWCLK, CE => ce_shdhead_tms, CLR => RST, Q => q2_shdhead_tms); --2nd bit sent
  FDPE_Q3SHDHEADTMS : FDPE port map(D => q2_shdhead_tms, C => SLOWCLK, CE => ce_shdhead_tms, PRE => RST, Q => q3_shdhead_tms); --1st bit sent




  -- Handle shifting data for all INSTSHFT and DATASHFT commands

  -- Assert shdata when busy, not shifting headers, and not yet done shifting data
  shdata  <= '1' when (busy = '1' and dheaden = '0' and iheaden = '0' and donedata(1) = '0') else '0';

  -- Generate DONEDATA using counter, d_donedata is asserted COMMAND(9 downto 6)*2 cycles after shdata is first asserted, donedata(0) and (1) are asserted on the
  -- next two clock edges in order
  dv_donedata  <= COMMAND(9 downto 6);
  ce_donedata  <= '1' when (shdata = '1' and tck_global = '1')                         else '0';
  clr_donedata <= '1' when (RST = '1' or donedata(1) = '1' or donedata(0) = '1') else '0';
  up_donedata  <= '0';                  -- connected to GND
  CB4CLED(SLOWCLK, ce_donedata, clr_donedata, load, up_donedata, dv_donedata, qv_donedata, qv_donedata, ceo_donedata, tc_donedata);  -- (C, CE, CLR, L, UP, D, Q_in, Q, CEO, TC)
  d_donedata   <= '1' when (qv_donedata = "0000" and load = '0')                 else '0';
  FDCE_DONEDATA0 : FDCE port map(D => d_donedata, C => SLOWCLK, CE => shdata, CLR => load, Q => donedata(0));
  FDC_DONEDATA1 : FDC port map(D => donedata(0), C => SLOWCLK, CLR => load, Q => donedata(1));




  -- Handle shifting TMS tailer for relevant INSTSHFT and DATASHFT commands (0x2Y08 0x2Y0C 0x2Y1C)

  -- Generate tailen cycle after load, shtail when busy is asserted and donedata(1)
  ce_tailen  <= '1' when (load = '1' and (instshft = '1' or datashft = '1')) else '0';
  clr_tailen <= '1' when (RST = '1' or donetail = '1')      else '0';
  FDCE_TAILEN : FDCE port map(D => COMMAND(1), C => SLOWCLK, CE => ce_tailen, CLR => clr_tailen, Q => tailen);
  shtail <= '1' when (busy = '1' and donedata(1) = '1' and tailen = '1') else '0';

  -- Generate donetail, reset to 0 on load and cycle after done, goes high 2 cycles after shtail enabled for special tailer and 4 otherwise
  clr_donetail <= '1' when (RST = '1' or q_donetail = '1') else '0';
  CB4CE(SLOWCLK, shtail, clr_donetail, qv_donetail, qv_donetail, ceo_donetail, tc_donetail); --(C, CE, CLR, Q_in, Q, CEO, TC)
  donetail     <= '1' when (qv_donetail="0100") else '0';
  FD_DONETAIL : FD_1 port map(D => donetail, C => SLOWCLK, Q => q_donetail);

  -- Generate TMS when shtail=1
  ce_shtail_tms <= '1'           when ((shtail = '1') and (tck_global = '1')) else '0';
  FDCE_Q1SHTAILTMS : FDCE port map(D => q2_shtail_tms, C => SLOWCLK, CE => ce_shtail_tms, CLR => RST, Q => q1_shtail_tms);
  FDCE_Q2SHTAILTMS : FDPE port map(D => q1_shtail_tms, C => SLOWCLK, CE => ce_shtail_tms, PRE => RST, Q => q2_shtail_tms);




  -- Setting polarity of JTAGSEL: default high
  rst_b           <= not RST;
  PULSERST : PULSE_EDGE port map(DOUT => rst_pulse, PULSE1 => open, CLK => SLOWCLK, RST => '0', NPULSE => 18, DIN => rst_b);
  rst_pulse_b     <= not rst_pulse;
  PULSEPOL : PULSE_EDGE port map(DOUT => pol_pulse, PULSE1 => open, CLK => SLOWCLK, RST => '0', NPULSE => 1, DIN => rst_pulse_b);
  FDCE_POLARITY : FDCE port map(D => default_high, C => SLOWCLK, CE => w_polarity, CLR => pol_pulse, Q => default_low);
  -- FDPE_POLARITY : FDPE port map(D => default_high, C => SLOWCLK, CE => w_polarity, PRE => pol_pulse, Q => default_low);
  default_high    <= not default_low;

-- DTACK polarity
  dd_dtack_pol <= '1' when (STROBE = '1' and DEVICE = '1')           else '0';
  FDCE_DDTACKPOL : FDCE port map(D => logich, C => SLOWCLK, CE => dd_dtack_pol, CLR => dtack_pol, Q => d_dtack_pol);
  FD_DTACKPOL : FD port map(D => d_dtack_pol, C => SLOWCLK, Q => dtack_pol);

  -- jtagsel_in <= (DEVICE and STROBE) or INITJTAGS;
  jtagsel_in <= resetjtag or busy or INITJTAGS;
  jtagsel_inner <= jtagsel_in when default_low = '1' else not jtagsel_in;
  --jtagsel_in <= (DEVICE and STROBE); -- For debug
  JTAGSEL <= jtagsel_inner;




  -- Handle central JTAG signals (TCK, TDI, TMS, TDO)

  -- Multiplex TMS's together
  TMS       <= q6_resetjtag_tms when (resetjtag = '1') else
               q4_shihead_tms when (shihead = '1') else
               q3_shdhead_tms when (shdhead = '1') else
               (tailen and d_donedata) when (shdata = '1') else
               q2_shtail_tms when (shtail = '1') else 'Z';

  tms_global <= q6_resetjtag_tms when (resetjtag = '1') else
               q4_shihead_tms when (shihead = '1') else
               q3_shdhead_tms when (shdhead = '1') else
               (tailen and d_donedata) when (shdata = '1') else
               q2_shtail_tms when (shtail = '1') else '0';


  -- Generate tck_global
  ce_tck_global <= '1' when (resetjtag = '1' or busy = '1') else '0';
  d_tck_global  <= not tck_global;
  FDCE_TCKGLOBAL : FDCE port map(D => d_tck_global, C => SLOWCLK, CE => ce_tck_global, CLR => RST, Q => tck_global);

  -- Generate TCK
  TCK <= tck_global;
  --TCK <= jtagsel_in and tck_global;
  --TCK <= ((DEVICE and STROBE) or INITJTAGS) and tck_global; -- For debug

  -- Generate LED.
  LED <= (DEVICE and STROBE) or INITJTAGS;

  -- Generate TDI
  TDI <= qv_tdi(0);
  tdi_global <= qv_tdi(0);
  ce_tdi <= (shdata and tck_global);
  SR16CLRE(SLOWCLK, ce_tdi, RST, load, qv_tdi(0), INDATA, qv_tdi, qv_tdi);

  -- Generate rdtdodk
  rdtdodk <= '1' when (STROBE = '1' and readtdo = '1' and busyp1 = '0' and busy = '0') else '0';

  -- Generate OUTDATA
  shft_en <= shdata and not tck_global;
  SR16LCE(SLOWCLK, shft_en, RST, ODMBTDO, q_outdata, q_outdata);
  OUTDATA(15 downto 0) <= q_outdata(15 downto 0) when (rdtdodk = '1') else (others => 'Z');
  tdo_global <= ODMBTDO;

  --Generate DTACK on cycle after rdtdodk
  FD_DTACKREADTDO : FD port map(D => rdtdodk, C => SLOWCLK, Q => dtack_readtdo);

  -- Handle DTACK
  DTACK <= '1' when (dtack_rstjtag = '1') or
           (dtack_readtdo = '1') or
           (dtack_shft = '1') else '0';

  dtack_ila <= '1' when (dtack_rstjtag = '1') or
           (dtack_readtdo = '1') or
           (dtack_shft = '1') else '0';

  -- i_ila : ila_odmbJTAG
  --     port map(
  --         clk => FASTCLK,
  --         probe0 => cmddev,
  --         probe1 => INDATA,
  --         probe2 => OUTDATA,
  --         probe3 => trigger,
  --         probe4 => data
  --         );
  --
  -- trigger(0) <= SLOWCLK;
  -- trigger(1) <= DEVICE;
  -- trigger(2) <= STROBE;
  -- trigger(3) <= resetjtag;
  -- trigger(4) <= datashft;
  -- trigger(5) <= instshft;
  -- trigger(6) <= readtdo;
  -- trigger(7) <= w_polarity;
  -- trigger(8) <= busy;
  -- trigger(9) <= load;
  -- trigger(10) <= shihead;
  -- trigger(11) <= shdhead;
  -- trigger(12) <= shdata;
  -- trigger(13) <= shtail;
  -- trigger(14) <= dtack_ila;
  --
  -- data(0) <= tms_global;
  -- data(1) <= tck_global;
  -- data(2) <= tdi_global;
  -- data(3) <= tdo_global;
  -- data(4) <= jtagsel_inner;


end ODMBJTAG_Arch;
