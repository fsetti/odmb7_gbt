-- VMEMON: Sends out FLFCTRL with monitoring values

library ieee;
library work;
library unisim;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ucsb_types.all;
use unisim.vcomponents.all;

--! @brief module that monitors various registers, sets certain voltaile settings, and sends reset signals
--! @details Supported VME commands:
--! * W/R 3000 write or read ODMB calibration mode. 0=nominal mode, 1=calibration mode (L1A with each pulse)
--! * W   3004 ODMB firmware soft reset
--! * W   3008 ODMB optical reset
--! * W   3010 DCFEB reprogram (hard reset)
--! * W   3014 L1A reset and DCFEB resync
--! * W/R 3020 write or read test point select 
--! * W/R 3024 write or read the maximum number of bad words from (x)DCFEB before they are killed
--! * W/R 3100 write or read loopback setting. 0=no loopback, 1 or 2=internal loopback
--! * R   3110 read TX voltage swing. 0=minimum (100 mV), F=maximum (1100 mV)
--! * R   3120 read (x)DCFEB programming done bits
--! * w   3200 generate pulses. bits: 0=INJPLS, 1=EXTPLS, 2=L1A+L1A_MATCH, 3=LCT request to OTMB, 4=external trigger request to OTMB, 5=BC0
--! * W/R 3300 write or read data multiplexer. 0=real data, 1=dummy data. 
--! * W/R 3304 write or read trigger multiplexer. 0=external triggers, 1=internal triggers.
--! * W/R 3308 write or read LVMB multiplexer. 0=real LVMB, 1=dummy LVMB.
--! * W/R 3400 write or read pedestal (L1A_MATCH for each L1A). 0=normal, 1=pedestal.
--! * W/R 3404 write or read. 0=normal, 1=OTMB data requested for each L1A.
--! * W/R 3408 write or read L1A mask. bit 0=kills L1A, bits 1-7=kills L1A_MATCHes 
--! * W/R 340C write or read mask_pls. 0=normal, 1=no EXTPLS/INJPLS
--! * R   3YZC read data registers. YZ determines the data to be read, see top level.
entity VMEMON is
  generic (
    NCFEB   : integer range 1 to 7 := 7
    );
  port (

    SLOWCLK : in std_logic;                                 --! 2.5 MHz clock.
    CLK40   : in std_logic;                                 --! 40 MHz clock. Used for resets and pulses.
    RST     : in std_logic;                                 --! Firmware soft reset signal.

    DEVICE  : in std_logic;                                 --! Indicates if this is the selected ODMB VME device.
    STROBE  : in std_logic;                                 --! Strobe signal indicating VME command is ready.
    COMMAND : in std_logic_vector(9 downto 0);              --! VME command signal.
    WRITER  : in std_logic;                                 --! Indicates if VME command is a read or write command.

    INDATA  : in  std_logic_vector(15 downto 0);            --! Input data accompanying VME command.
    OUTDATA : out std_logic_vector(15 downto 0);            --! Output data to VME backplane.

    DTACK : out std_logic;                                  --! Data acknowledge, indicates the VME command has been received.

    DCFEB_DONE  : in std_logic_vector(NCFEB downto 1);      --! DCFEB done bits.

    --reset signals
    OPT_RESET_PULSE : out std_logic;                        --! Signal to reset optical firmware.
    L1A_RESET_PULSE : out std_logic;                        --! Signal to reset L1A counter.
    FW_RESET        : out std_logic;                        --! ODMB firmware soft reset signal
    REPROG_B        : out std_logic;                        --! REPROGRAM signal to (x)DCFEBs.

    --pulses
    TEST_INJ        : out std_logic;                        --! Signal to generate test INJPLS to (x)DCFEBs.
    TEST_PLS        : out std_logic;                        --! Signal to generate test EXTPLS to (x)DCFEBs.
    TEST_LCT        : out std_logic;                        --! Signal to generate test LCTs to (x)DCFEBs.
    TEST_BC0        : out std_logic;                        --! Signal to generate test BC0 to (x)DCFEBs.
    OTMB_LCT_RQST   : out std_logic;                        --! LCT request signal to OTMB.
    OTMB_EXT_TRIG   : out std_logic;                        --! External trigger request signal to OTMB.

    --internal register outputs
    ODMB_CAL        : out std_logic;                        --! Sets calibration mode (L1A generated with INJPLS) in TRGCTRL.
    TP_SEL          : out std_logic_vector(15 downto 0);    --! Test point select signal.
    MAX_WORDS_DCFEB : out std_logic_vector(15 downto 0);    --! Maximum number of words before an (x)DCFEB is marked as bad.
    LOOPBACK        : out std_logic_vector(2 downto 0);     --! For internal loopback tests, currently unused.
    TXDIFFCTRL      : out std_logic_vector(3 downto 0);     --! Controls the TX voltage swing, currently unused.
    MUX_DATA_PATH   : out std_logic;                        --! Controls whether data comes from real boards or simulated data.
    MUX_TRIGGER     : out std_Logic;                        --! Controls whether trigger signals are external or come from TESTCTRL.
    MUX_LVMB        : out std_logic;                        --! Controls whether LVMB communication is to real board or simulated LVMB.
    ODMB_PED        : out std_logic_vector(1 downto 0);     --! Controls pedestal (genereates L1A MATCH for each L1A)
    TEST_PED        : out std_logic;                        --! Control whether OTMB data is requested for each L1A.
    MASK_L1A        : out std_logic_vector(NCFEB downto 0); --! Suppresses L1A and L1A_MATCHes.
    MASK_PLS        : out std_logic;                        --! Suppresses INJPLS and EXTPLS signals.

    --exernal registers
    ODMB_STAT_SEL   : out std_logic_vector(7 downto 0);     --! Selects top level data signal to read.
    ODMB_STAT_DATA  : in  std_logic_vector(15 downto 0)     --! Data from top level.
    );
end VMEMON;


architecture VMEMON_Arch of VMEMON is

  --command interpretation
  signal cmddev : std_logic_vector (15 downto 0);

  --reset signals
  signal w_odmb_rst     : std_logic := '0';
  signal w_dcfeb_reprog : std_logic := '0';
  signal w_dcfeb_resync : std_logic := '0';
  signal w_opt_rst      : std_logic := '0';
  signal reprog         : std_logic := '0';

  --internal registers (+dcfeb done)  write/read signals
  signal out_odmb_cal           : std_logic_vector(15 downto 0) := (others => '0');
  signal w_odmb_cal, r_odmb_cal : std_logic                     := '0';
  signal odmb_cal_inner       : std_logic                     := '0';

  signal out_tp_sel, tp_sel_inner : std_logic_vector(15 downto 0) := (others => '0');
  signal w_tp_sel                 : std_logic                     := '0';
  signal r_tp_sel                 : std_logic                     := '0';

  signal out_max_words_dcfeb, max_words_dcfeb_inner : std_logic_vector(15 downto 0) := (others => '0');
  signal w_max_words_dcfeb                 : std_logic                     := '0';
  signal r_max_words_dcfeb                 : std_logic                     := '0';

  signal out_loopback   : std_logic_vector(15 downto 0) := (others => '0');
  signal loopback_inner : std_logic_vector(2 downto 0)  := (others => '0');
  signal w_loopback     : std_logic                     := '0';
  signal r_loopback     : std_logic                     := '0';

  signal out_txdiffctrl   : std_logic_vector(15 downto 0) := (others => '0');
  signal txdiffctrl_inner : std_logic_vector(3 downto 0);
  signal r_txdiffctrl     : std_logic                     := '0';

  signal out_dcfeb_done : std_logic_vector(15 downto 0) := (others => '0');
  signal r_dcfeb_done   : std_logic                     := '0';

  signal out_mux_data_path                : std_logic_vector(15 downto 0) := (others => '0');
  signal w_mux_data_path, r_mux_data_path : std_logic                     := '0';
  signal mux_data_path_inner          : std_logic                     := '0';

  signal out_mux_trigger              : std_logic_vector(15 downto 0) := (others => '0');
  signal w_mux_trigger, r_mux_trigger : std_logic                     := '0';
  signal mux_trigger_inner        : std_logic                     := '0';

  signal out_mux_lvmb           : std_logic_vector(15 downto 0) := (others => '0');
  signal w_mux_lvmb, r_mux_lvmb : std_logic                     := '0';
  signal mux_lvmb_inner     : std_logic                     := '0';

  signal out_odmb_ped           : std_logic_vector(15 downto 0) := (others => '0');
  signal w_odmb_ped, r_odmb_ped : std_logic                     := '0';
  signal odmb_ped_inner         : std_logic_vector(1 downto 0)  := (others => '0');

  signal out_test_ped                           : std_logic_vector(15 downto 0) := (others => '0');
  signal w_test_ped, r_test_ped, test_ped_inner : std_logic                     := '0';

  signal out_mask_pls           : std_logic_vector(15 downto 0)   := (others => '0');
  signal mask_pls_inner         : std_logic                       := '0';
  signal w_mask_pls, r_mask_pls : std_logic                       := '0';

  signal out_mask_l1a           : std_logic_vector(15 downto 0)   := (others => '0');
  signal mask_l1a_inner         : std_logic_vector(NCFEB downto 0) := (others => '0');
  signal w_mask_l1a, r_mask_l1a : std_logic                       := '0';

  --external read signals
  signal r_odmb_data : std_logic;

  --dcfeb pulse signals
  signal w_dcfeb_pulse : std_logic                    := '0';
  signal dcfeb_pulse   : std_logic_vector(5 downto 0) := (others => '0');

  --dtack signals
  signal ce_d_dtack, d_dtack, q_dtack : std_logic;

begin

  -- Decode commands
  -- CMDDEV: Variable that looks like the VME commands we input
  cmddev <= "000" & DEVICE & COMMAND & "00";

  w_odmb_cal        <= '1' when (CMDDEV = x"1000" and WRITER = '0' and STROBE = '1') else '0';
  r_odmb_cal        <= '1' when (CMDDEV = x"1000" and WRITER = '1') else '0';

  w_odmb_rst        <= '1' when (CMDDEV = x"1004" and WRITER = '0' and STROBE = '1') else '0';
  w_opt_rst         <= '1' when (CMDDEV = x"1008" and WRITER = '0' and STROBE = '1') else '0';
  w_dcfeb_reprog    <= '1' when (CMDDEV = x"1010" and WRITER = '0' and STROBE = '1') else '0';
  w_dcfeb_resync    <= '1' when (CMDDEV = x"1014" and WRITER = '0' and STROBE = '1') else '0';

  w_tp_sel          <= '1' when (CMDDEV = x"1020" and WRITER = '0' and STROBE = '1') else '0';
  r_tp_sel          <= '1' when (CMDDEV = x"1020" and WRITER = '1') else '0';
  w_max_words_dcfeb <= '1' when (CMDDEV = x"1024" and WRITER = '0' and STROBE = '1') else '0';
  r_max_words_dcfeb <= '1' when (CMDDEV = x"1024" and WRITER = '1') else '0';

  w_loopback        <= '1' when (CMDDEV = x"1100" and WRITER = '0' and STROBE = '1') else '0';
  r_loopback        <= '1' when (CMDDEV = x"1100" and WRITER = '1') else '0';
  -- w_txdiffctrl      <= '1' when (CMDDEV = x"1110" and WRITER = '0') else '0'; -- obsolete
  r_txdiffctrl      <= '1' when (CMDDEV = x"1110" and WRITER = '1') else '0';
  r_dcfeb_done      <= '1' when (CMDDEV = x"1120" and WRITER = '1') else '0';
  -- r_qpll_locked     <= '1' when (CMDDEV = x"1124" and WRITER = '1') else '0'; --obsolete on ODMB7/5

  w_dcfeb_pulse     <= '1' when (CMDDEV = x"1200" and WRITER = '0' and STROBE = '1') else '0';

  w_mux_data_path   <= '1' when (CMDDEV = x"1300" and WRITER = '0' and STROBE = '1') else '0';
  r_mux_data_path   <= '1' when (CMDDEV = x"1300" and WRITER = '1') else '0';
  w_mux_trigger     <= '1' when (CMDDEV = x"1304" and WRITER = '0' and STROBE = '1') else '0';
  r_mux_trigger     <= '1' when (CMDDEV = x"1304" and WRITER = '1') else '0';
  w_mux_lvmb        <= '1' when (CMDDEV = x"1308" and WRITER = '0' and STROBE = '1') else '0';
  r_mux_lvmb        <= '1' when (CMDDEV = x"1308" and WRITER = '1') else '0';

  w_odmb_ped        <= '1' when (CMDDEV = x"1400" and WRITER = '0' and STROBE = '1') else '0';
  r_odmb_ped        <= '1' when (CMDDEV = x"1400" and WRITER = '1') else '0';
  w_test_ped        <= '1' when (CMDDEV = x"1404" and WRITER = '0' and STROBE = '1') else '0';
  r_test_ped        <= '1' when (CMDDEV = x"1404" and WRITER = '1') else '0';
  w_mask_l1a        <= '1' when (CMDDEV = x"1408" and WRITER = '0' and STROBE = '1') else '0';
  r_mask_l1a        <= '1' when (CMDDEV = x"1408" and WRITER = '1') else '0';
  w_mask_pls        <= '1' when (CMDDEV = x"140C" and WRITER = '0' and STROBE = '1') else '0';
  r_mask_pls        <= '1' when (CMDDEV = x"140C" and WRITER = '1') else '0';

  -- R 3XYC "Read external registers XY (where XY /= 40)"
  r_odmb_data       <= '1' when ((CMDDEV and x"100C") = x"100C" and CMDDEV /= x"140C" and WRITER = '1') else '0';
  ODMB_STAT_SEL     <= COMMAND(9 downto 2) when (r_odmb_data = '1') else x"1F";

  -- Reset command(0x3004 0x3008 0x3010 0x3014)
  -- DCFEB Reprog is asserted for the 2 clock cycles in SLOWCLK after STROBE, others are asserted for 1 cycle in CLK40 1 cycle after STROBE
  PLS_FWRESET  : PULSE2FAST port map(DOUT => FW_RESET, CLK_DOUT => CLK40, RST => RST, DIN => w_odmb_rst);
  PLS_OPTRESET : PULSE2FAST port map(DOUT => OPT_RESET_PULSE, CLK_DOUT => CLK40, RST => RST, DIN => w_opt_rst);
  PLS_L1ARESET : PULSE2FAST port map(DOUT => L1A_RESET_PULSE, CLK_DOUT => CLK40, RST => RST, DIN => w_dcfeb_resync);
  PLS_REPROG   : NPULSE2SAME port map(DOUT => reprog, CLK_DOUT => SLOWCLK, RST => RST, NPULSE => 2, DIN => w_dcfeb_reprog);
  -- REPROG_B <= not reprog;
  REPROG_B <= '1';

  --Local register (+DCFEB done) write/read commands

  --0x3000 write/read calib mode
  FD_TESTCAL : FDCE port map(Q => odmb_cal_inner, C => SLOWCLK, CE => w_odmb_cal, CLR => RST, D => INDATA(0));
  ODMB_CAL <= odmb_cal_inner;
  out_odmb_cal <= x"000" & "000"  & odmb_cal_inner;

  --0x3020 Write/read TP_SEL
  GEN_TP_SEL : for I in 15 downto 0 generate
  begin
    FD_W_TP_SEL : FDCE port map(Q => tp_sel_inner(I), C => SLOWCLK, CE => w_tp_sel, CLR => RST, D => INDATA(I));
  end generate GEN_TP_SEL;
  TP_SEL <= tp_sel_inner;
  out_tp_sel(15 downto 0) <= tp_sel_inner;

  --0x3024 Write/read MAX_WORDS_DCFEB. At reset it goes to 2^10 = 1024
  GEN_MAX_WORDS_DCFEB : for I in 9 downto 0 generate
  begin
    FD_W_MAX_WORDS_DCFEB0 : FDCE port map(Q => max_words_dcfeb_inner(I), C => SLOWCLK, CE => w_max_words_dcfeb, CLR => RST, D => INDATA(I));
  end generate GEN_MAX_WORDS_DCFEB;
  GEN_MAX_WORDS_DCFEB11 : for I in 15 downto 11 generate
  begin
    FD_W_MAX_WORDS_DCFEB11 : FDCE port map(Q => max_words_dcfeb_inner(I), C => SLOWCLK, CE => w_max_words_dcfeb, CLR => RST, D => INDATA(I));
  end generate GEN_MAX_WORDS_DCFEB11;
  FD_W_MAX_WORDS_DCFEB10 : FDPE port map(Q => max_words_dcfeb_inner(10), C => SLOWCLK, CE => w_max_words_dcfeb, PRE => RST, D => INDATA(10));
  MAX_WORDS_DCFEB <= max_words_dcfeb_inner;
  out_max_words_dcfeb(15 downto 0) <= max_words_dcfeb_inner;

  --0x3100 write/read LOOPBACK
  GEN_LOOPBACK : for I in 2 downto 0 generate
  begin
    FD_W_LOOPBACK : FDCE port map(Q => loopback_inner(I), C => SLOWCLK, CE => w_loopback, CLR => RST, D => INDATA(I));
  end generate GEN_LOOPBACK;
  LOOPBACK <= loopback_inner;
  out_loopback <= x"000" & '0' & loopback_inner;

  --0x3110 read TX voltage control
  txdiffctrl_inner <= x"8";
  TXDIFFCTRL <= txdiffctrl_inner;
  out_txdiffctrl    <= x"000" & txdiffctrl_inner;

  --0x3120 read DCFEB done (NOT local register)
  out_dcfeb_done <= x"00" & '0' & dcfeb_done;

  --0x3300 write/read data path MUX selector
  FD_MUXDATAPATHSEL : FDCE port map(Q => mux_data_path_inner, C => SLOWCLK, CE => w_mux_data_path, CLR => RST, D => INDATA(0));
  MUX_DATA_PATH <= mux_data_path_inner;
  out_mux_data_path <= x"000" & "000" & mux_data_path_inner;

  --0x3304 write/read trigger MUX selector
  FD_MUXTRIGGERSEL : FDCE port map(Q => mux_trigger_inner, C => SLOWCLK, CE => w_mux_trigger, CLR => RST, D => INDATA(0));
  MUX_TRIGGER <= mux_trigger_inner;
  out_mux_trigger   <= x"000" & "000" & mux_trigger_inner;

  --0x3308 write/read LVMB MUX selector
  FD_MUXLVMBSEL : FDCE port map(Q => mux_lvmb_inner, C => SLOWCLK, CE => w_mux_lvmb, CLR => RST, D => INDATA(0));
  MUX_LVMB <= mux_lvmb_inner;
  out_mux_lvmb <= x"000" & "000" & mux_lvmb_inner;

  --0x3400 write/read pedestal mode
  FD_ODMBPED1 : FDCE port map(Q => odmb_ped_inner(0), C => SLOWCLK, CE => w_odmb_ped, CLR => RST, D => INDATA(0));
  FD_ODMBPED2 : FDCE port map(Q => odmb_ped_inner(1), C => SLOWCLK, CE => w_odmb_ped, CLR => RST, D => INDATA(1));
  ODMB_PED <= odmb_ped_inner;
  out_odmb_ped <= x"000" & "00"  & odmb_ped_inner;

  --0x3404 write/read OTMB test pedestal mode
  FD_TESTPED : FDCE port map(Q => test_ped_inner, C => SLOWCLK, CE => w_test_ped, CLR => RST, D => INDATA(0));
  TEST_PED <= test_ped_inner;
  out_test_ped <= x"000" & "000" & test_ped_inner;

  --0x340C write/read MASK_PLS
  FD_W_MASK_PLS : FDCE port map(Q => mask_pls_inner, C => SLOWCLK, CE => w_mask_pls, CLR => RST, D => INDATA(0));
  MASK_PLS <= mask_pls_inner;
  out_mask_pls(15 downto 0) <= x"000" & "000" & mask_pls_inner;

  --0x3408 Write/read MASK_L1A
  GEN_MASK_L1A : for I in NCFEB downto 0 generate
  begin
    FD_W_MASK_L1A : FDCE port map(Q => mask_l1a_inner(I), C => SLOWCLK, CE => w_mask_l1a, CLR => RST, D => INDATA(I));
  end generate GEN_MASK_L1A;
  MASK_L1A <= mask_l1a_inner;
  out_mask_l1a(15 downto 0) <= x"00" & mask_l1a_inner;

  -- DCFEB pulses
  GEN_dcfeb_pulse : for K in 0 to 5 generate
  begin
    dcfeb_pulse(K) <= w_dcfeb_pulse and STROBE and INDATA(K);
  end generate GEN_dcfeb_pulse;
  PULSE_INJ : NPULSE2SAME port map(DOUT => TEST_INJ, CLK_DOUT => SLOWCLK, RST => RST, NPULSE => 2, DIN => dcfeb_pulse(0));
  PULSE_PLS : NPULSE2SAME port map(DOUT => TEST_PLS, CLK_DOUT => SLOWCLK, RST => RST, NPULSE => 2, DIN => dcfeb_pulse(1));
  PULSE_L1A : PULSE2FAST port map(DOUT => TEST_LCT, CLK_DOUT => CLK40, RST => rst, DIN => dcfeb_pulse(2));
  PULSE_LCT : PULSE2FAST port map(DOUT => OTMB_LCT_RQST, CLK_DOUT => CLK40, RST => rst, DIN => dcfeb_pulse(3));
  PULSE_EXT : PULSE2FAST port map(DOUT => OTMB_EXT_TRIG, CLK_DOUT => CLK40, RST => rst, DIN => dcfeb_pulse(4));
  PULSE_BC0 : PULSE2FAST port map(DOUT => TEST_BC0, CLK_DOUT => CLK40, RST => rst, DIN => dcfeb_pulse(5));

  -- MUX outdata
  OUTDATA <= out_odmb_cal        when (r_odmb_cal = '1')        else
             out_tp_sel          when (r_tp_sel = '1')          else
             out_max_words_dcfeb when (r_max_words_dcfeb = '1') else
             out_loopback        when (r_loopback = '1')        else
             out_txdiffctrl      when (r_txdiffctrl = '1')      else
             out_dcfeb_done      when (r_dcfeb_done = '1')      else
             out_mux_data_path   when (r_mux_data_path = '1')   else
             out_mux_trigger     when (r_mux_trigger = '1')     else
             out_mux_lvmb        when (r_mux_lvmb = '1')        else
             out_odmb_ped        when (r_odmb_ped = '1')        else
             out_test_ped        when (r_test_ped = '1')        else
             out_mask_pls        when (r_mask_pls = '1')        else
             out_mask_l1a        when (r_mask_l1a = '1')        else
             ODMB_STAT_DATA      when (r_odmb_data = '1')       else
             (others => 'L');

  -- DTACK: always just issue on second SLOWCLK edge after STROBE
  ce_d_dtack <= STROBE and DEVICE;
  FD_D_DTACK : FDCE port map(Q => d_dtack, C => SLOWCLK, CE => ce_d_dtack, CLR => q_dtack, D => '1');
  FD_Q_DTACK : FD port map(Q => q_dtack, C => SLOWCLK, D => d_dtack);
  DTACK    <= q_dtack;

end VMEMON_Arch;
