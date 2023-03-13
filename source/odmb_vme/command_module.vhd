library ieee;
use ieee.std_logic_1164.all;
library UNISIM;
use UNISIM.vcomponents.all;
library work;
-- library hdlmacro;

--! @brief module that interprets VME commands for modules in ODMB VME
entity COMMAND_MODULE is
  port (

    FASTCLK : in std_logic;                      --! 40 MHz clock
    SLOWCLK : in std_logic;                      --! 2.5 MHz clock

    GAP     : in std_logic;                      --! Geographical address parity, must match GA
    GA      : in std_logic_vector(4 downto 0);   --! Crate geographical address, checked against command
    ADR     : in std_logic_vector(23 downto 1);  --! VME ADDR (command), must match GA
    AM      : in std_logic_vector(5 downto 0);   --! VME address modifier, must be 111X10 or 111X01

    AS      : in std_logic;                      --! Address strobe, indicates AM and ADR can be read
    DS0     : in std_logic;                      --! Data strobe, indicates data is ready
    DS1     : in std_logic;                      --! Data strobe, indicates data is ready
    LWORD   : in std_logic;                      --! VME word length, must be 1
    WRITER  : in std_logic;                      --! VME read(1)/write(0), only used for debug
    IACK    : in std_logic;                      --! VME Interrupt acknowledge bar, must be 1
    BERR    : in std_logic;                      --! VME bus error bar, unused
    SYSFAIL : in std_logic;                      --! VME system fail bar, must be 1

    DEVICE  : out std_logic_vector(9 downto 0);  --! Output to select VME device for command
    STROBE  : out std_logic;                     --! Signal to initiate interpretation of VME command
    COMMAND : out std_logic_vector(9 downto 0);  --! VME command output (subset of VME ADDR)
    ADRS    : out std_logic_vector(17 downto 2); --! Output to select VME device to multiplex to VME

    TOVME_B : out std_logic;                     --! Selects VME input/output direction
    DOE_B   : out std_logic;                     --! VME output enable to ODMB ICs

    DIAGOUT : out std_logic_vector(17 downto 0); --! Debug signals
    LED     : out std_logic_vector(2 downto 0)   --! Debug signals

    );
end COMMAND_MODULE;

architecture COMMAND_MODULE_Arch of COMMAND_MODULE is

  --Declaring internal signals
  signal CGA           : std_logic_vector(5 downto 0);  --NOTE: replacing CGAP with CGA(5)
  signal AMS           : std_logic_vector(5 downto 0);
  signal ADRS_INNER    : std_logic_vector(23 downto 1);
  signal GOODAM        : std_logic;
  signal VALIDAM       : std_logic;
  signal VALIDGA       : std_logic;
  signal SYSOK         : std_logic;
  signal OLDCRATE      : std_logic;
  signal PRE_BOARDENB  : std_logic;
  signal BROADCAST     : std_logic;
  signal BOARDENB      : std_logic;
  signal BOARD_SEL_NEW : std_logic;
  signal ASYNSTRB      : std_logic;
  signal ASYNSTRB_NOT  : std_logic;
  signal FASTCLK_NOT   : std_logic;
  signal STROBE_TEMP1  : std_logic;
  signal STROBE_TEMP2  : std_logic;
  signal ADRSHIGH      : std_logic;

  signal D1, C1, Q1, D2, C2, Q2, D3, C3, Q3, D4, C4                                             : std_logic;
  signal D1_second, C1_second, Q1_second, D2_second, C2_second, Q2_seconD                       : std_logic;
  signal D3_second, C3_second, Q3_second, D4_second, C4_second, Q4_second, D5_second, C5_second : std_logic;
  signal TOVME_INNER                                                                            : std_logic;

  signal CE_DOE_B, CLR_DOE_B : std_logic;
  signal TIMER               : std_logic_vector(7 downto 0);
  signal TOVME_INNER_B       : std_logic;
  signal ADRSDEV             : std_logic_vector(4 downto 0);

  -- 8-Bit Cascadable Binary Counter with Clock Enable and Asynchronous Clear
  component CB8CE
    port (
      CEO : out std_logic;
      Q   : out std_logic_vector(7 downto 0);
      TC  : out std_logic;
      C   : in std_logic;
      CE  : in std_logic;
      CLR : in std_logic
      );
  end component;

begin  --Architecture

  -- Generate DOE_B
  CE_DOE_B  <= '1' when TOVME_INNER_B = '0' and TIMER(7) = '0' else '0';
  CLR_DOE_B <= TOVME_INNER_B;
  CB8CE_DOE : CB8CE port map (CEO => open, Q => TIMER, TC => open, C => SLOWCLK, CE => CE_DOE_B, CLR => CLR_DOE_B);
  DOE_B     <= TIMER(7);

  -- Generate VALIDGA
  CGA     <= (not GAP) & (not GA);
  VALIDGA <= '1' when ((CGA(0) xor CGA(1) xor CGA(2) xor CGA(3) xor CGA(4) xor CGA(5)) = '1') else '0';

  -- Generate OLDCRATE / Generate AMS / Generate VALIDAM / Generate GOODAM / Generate FASTCLK_NOT
  OLDCRATE <= '1' when CGA = "000000" else '0';

  VALIDAM     <= '1' when (AMS(0) /= AMS(1) and AMS(5 downto 3) = "111" and LWORD = '1') else '0';
  GOODAM      <= '1' when (AMS(0) /= AMS(1) and AMS(5 downto 3) = "111" and LWORD = '1') else '0';
  FASTCLK_NOT <= not FASTCLK;

  -- Load ADR and AM upon receiving AS
  process(FASTCLK, AS)
  begin
    if rising_edge(FASTCLK) then
      if (AS = '1') then
        AMS <= AM;
        ADRS_INNER <= ADR;
      end if;
    end if;
  end process;
  
  BOARD_SEL_NEW <= '1' when (ADRS_INNER(23 downto 19) = CGA(4 downto 0))              else '0';
  PRE_BOARDENB  <= '1' when (BOARD_SEL_NEW = '1' and VALIDGA = '1')                   else '0';
  BROADCAST     <= '1' when (ADRS_INNER(23 downto 19) = "11111")                      else '0';
  BOARDENB      <= '1' when (OLDCRATE = '1' or PRE_BOARDENB = '1' or BROADCAST = '1') else '0';
  SYSOK         <= '1' when (SYSFAIL = '1' and IACK = '1')                            else '0';

  (TOVME_INNER_B, TOVME_B, LED(0)) <= std_logic_vector'("001") when (GOODAM = '1' and WRITER = '1' and SYSOK = '1' and BOARDENB = '1') else
                                      std_logic_vector'("110");
  ASYNSTRB     <= '1' when (SYSOK = '1' and VALIDAM = '1' and BOARDENB = '1' and DS0 = '0' and DS1 = '0') else '0';
  ASYNSTRB_NOT <= not ASYNSTRB;

  FDC_STROBE   : FDC port map(Q => STROBE_TEMP1, C => FASTCLK, CLR => ASYNSTRB_NOT, D => ASYNSTRB);
  FDC_1_STROBE : FDC_1 port map(Q => STROBE_TEMP2, C => FASTCLK, CLR => ASYNSTRB_NOT, D => ASYNSTRB);
  STROBE <= '1' when (STROBE_TEMP1 = '1' and STROBE_TEMP2 = '1') else '0';

  -- Generate LED(1) / Generate LED(2)
  LED(1) <= not ASYNSTRB;
  LED(2) <= '0' when (STROBE_TEMP1 = '1' and STROBE_TEMP2 = '1') else '1';

  -- Generate DIAGOUT -Guido-
  DIAGOUT(0)  <= ADRS_INNER(18);
  DIAGOUT(1)  <= ADRS_INNER(19);
  DIAGOUT(2)  <= ADRS_INNER(20);
  DIAGOUT(3)  <= ADRS_INNER(21);
  DIAGOUT(4)  <= ADRS_INNER(22);
  DIAGOUT(5)  <= IACK;
  DIAGOUT(6)  <= AMS(0);
  DIAGOUT(7)  <= AMS(1);
  DIAGOUT(8)  <= AMS(2);
  DIAGOUT(9)  <= AMS(3);
  DIAGOUT(10) <= ASYNSTRB;
  DIAGOUT(11) <= DS1;
  DIAGOUT(12) <= DS0;
  DIAGOUT(13) <= BOARDENB;
  DIAGOUT(14) <= VALIDAM;
  DIAGOUT(15) <= SYSOK;
  DIAGOUT(16) <= STROBE_TEMP1;
  DIAGOUT(17) <= STROBE_TEMP2;
  --DIAGOUT(18) <= STROBE_TEMP2;
  --DIAGOUT(19) <= VALIDGA;

  -- Generate COMMAND
  COMMAND(9 downto 0) <= ADRS_INNER(11 downto 2);

  -- Generate ADRS
  ADRS <= ADRS_INNER(17 downto 2);

  -- Generate DEVICE
  ADRSHIGH <= '1' when (ADRS_INNER(18) = '1' or ADRS_INNER(17) = '1' or ADRS_INNER(16) = '1') else '0';
  ADRSDEV  <= ADRSHIGH & ADRS_INNER(15) & ADRS_INNER(14) & ADRS_INNER(13) & ADRS_INNER(12);

  with ADRSDEV select
    DEVICE <= "0000000001" when "00000",
    "0000000010"           when "00001",
    "0000000100"           when "00010",
    "0000001000"           when "00011",
    "0000010000"           when "00100",
    "0000100000"           when "00101",
    "0001000000"           when "00110",
    "0010000000"           when "00111",
    "0100000000"           when "01000",
    "1000000000"           when "01001",
    "0000000000"           when others;
  
end COMMAND_MODULE_Arch;

