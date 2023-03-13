library IEEE;
use IEEE.STD_LOGIC_1164.all;

Library UNISIM;

use UNISIM.vcomponents.all;
--use UNISIM.vpck.all;
--use work.Latches_Flipflops.all;

entity  CCBCODE is
  port (
    CCB_CMD : in std_logic_vector(5 downto 0);
    CCB_CMD_S : in std_logic;
    CCB_DATA : in std_logic_vector(7 downto 0);
    CCB_DATA_S : in std_logic;
    CMSCLK : in std_logic;
    CCB_BXRST_B : in std_logic;
    CCB_BX0_B : in std_logic;
    CCB_L1ARST_B : in std_logic;
    CCB_CLKEN : in std_logic;
    BX0 : out std_logic;
    BXRST : out std_logic;
    L1ARST : out std_logic;
    CLKEN : out std_logic;
    BC0 : out std_logic;  
    L1ASRST : out std_logic;
    TTCCAL : out std_logic_vector(2 downto 0)
    );
end CCBCODE;

architecture CCBCODE_arch of CCBCODE is

  component CB4CE is
  port (
      C       : in  std_logic;
      CE      : in  std_logic;
      CLR     : in  std_logic;
      Q_in    : in std_logic_vector(3 downto 0);
      Q       : out std_logic_vector(3 downto 0);
      CEO     : out std_logic;
      TC      : out std_logic
      );
  end component;
  
 -- signal RSTDATA : std_logic;
  signal BC0_CMD, BC0_RST, BC0_INNER : std_logic;
  signal START_TRG_CMD, START_TRG_RST, START_TRG_INNER : std_logic;
  signal STOP_TRG_CMD, STOP_TRG_RST, STOP_TRG_INNER : std_logic;
  signal L1ASRST_CMD, L1ASRST_RST, L1ASRST_CLK_CMD, L1ASRST_CNT_RST, L1ASRST_CNT_CEO, L1ASRST_INNER : std_logic;
  signal L1ASRST_CNT : std_logic_vector(3 downto 0);
  signal TTCCAL_CMD, TTCCAL_RST, TTCCAL_INNER : std_logic_vector(2 downto 0);
  signal CCBINJIN_1 : std_logic;
  signal CCBINJIN_2 : std_logic;
  signal CCBINJIN_3 : std_logic;
  signal CCBPLSIN_1 : std_logic;
  signal CCBPLSIN_2 : std_logic;
  signal CCBPLSIN_3 : std_logic;
  signal PLSINJEN_1 : std_logic;
  signal PLSINJEN_RST : std_logic;
  signal PLSINJEN_INV : std_logic;
  signal BX0_B : std_logic;
  signal BXRST_B : std_logic;
  signal CLKEN_B : std_logic;
  signal L1ARST_B : std_logic;

  signal LOGICH : std_logic := '1';

  -- commands implemented in this architecture
  -- 111110 ---> generate BC0
  -- 111001 ---> generate START_TRG
  -- 111000 ---> generate STOP_TRG
  -- 111000 ---> generate L1ASRST      
  -- 101011 ---> generate TTCCAL(0)
  -- 101010 ---> generate TTCCAL(1)
  -- 101001 ---> generate TTCCAL(2)    

begin

  -- generate RSTDATA replace with the following (apparently NOT used)
  -- RSTDATA <= '1' when (CCB_CMD_S = '0' and CCB_DATA(7 downto 1) = "1010101") else '0';

  -- generate BC0
  BC0_CMD <= '1' when (CCB_CMD_S = '0' and CCB_CMD(5 downto 0) = "111110") else '0';
  BC0_GEN: FDC port map (Q => BC0_INNER, C => CMSCLK, CLR => BC0_RST, D => BC0_CMD);
  BC0_RST_GEN : FD_1 port map (Q => BC0_RST, C => CMSCLK, D => BC0_INNER);
  BC0 <= BC0_INNER;
  
  -- generate START_TRG command
  START_TRG_CMD <= '1' when (CCB_CMD_S = '0' and   CCB_CMD(5 downto 0) = "111001") else '0';
  START_TRG_GEN : FDC port map (Q => START_TRG_INNER, C => CMSCLK, CLR => START_TRG_RST,  D => START_TRG_CMD);
  START_TRG_RST_GEN : FD_1 port map (Q => START_TRG_RST, C => CMSCLK, D => START_TRG_INNER);

  -- generate STOP_TRG command
  STOP_TRG_CMD <= '1' when (CCB_CMD_S = '0' and   CCB_CMD(5 downto 0) = "111000") else '0';
  STOP_TRG_GEN : FDC port map (Q => STOP_TRG_INNER, C => CMSCLK, CLR => STOP_TRG_RST,  D => STOP_TRG_CMD);
  STOP_TRG_RST_GEN : FD_1 port map (Q => STOP_TRG_RST, C => CMSCLK, D => STOP_TRG_INNER);

  -- generate L1ASRST
  L1ASRST_CMD <= '1' when (CCB_CMD(5 downto 0) = "111100" and CCB_CMD_S = '0') else '0';
  L1ARSTCMD_GEN : FD port map (Q => L1ASRST_CLK_CMD, C => CMSCLK, D => L1ASRST_CMD);
  L1ARSTINNER_GEN : FDC port map (Q => L1ASRST_INNER, C => L1ASRST_CLK_CMD, CLR => L1ASRST_RST, D => LOGICH);
  L1ASRST_CNT_RST <= not L1ASRST_INNER;
  CB4CE_L1ARST : CB4CE port map (C => CMSCLK, CE => L1ASRST_INNER, CLR => L1ASRST_CNT_RST, Q_in => L1ASRST_CNT, Q => L1ASRST_CNT, CEO => L1ASRST_CNT_CEO, TC => L1ASRST_RST);
  L1ASRST <= L1ASRST_INNER;
  
  -- generate TTCCAL
  TTCCAL_CMD(0) <= '1' when (CCB_CMD_S = '0' and   CCB_CMD(5 downto 0) = "101011") else '0';
  TTCCAL_GEN : FDC port map (Q => TTCCAL_INNER(0), C => CMSCLK, CLR => TTCCAL_RST(0), D => TTCCAL_CMD(0));
  TTCCAL_RST_GEN : FD port map (Q => TTCCAL_RST(0), C => CMSCLK, D => TTCCAL_INNER(0));

  TTCCAL_CMD(1) <= '1' when (CCB_CMD_S = '0' and   CCB_CMD(5 downto 0) = "101010") else '0';
  TTCCAL1_GEN : FDC port map (Q => TTCCAL_INNER(1), C => CMSCLK, CLR => TTCCAL_RST(1), D => TTCCAL_CMD(1) );
  TTCCAL1_RST_GEN : FD port map (Q => TTCCAL_RST(1), C => CMSCLK, D => TTCCAL_INNER(1));

  TTCCAL_CMD(2) <= '1' when (CCB_CMD_S = '0' and   CCB_CMD(5 downto 0) = "101001") else '0';
  TTCCAL2_GEN : FDC port map (Q => TTCCAL_INNER(2), C => CMSCLK, CLR => TTCCAL_RST(2), D => TTCCAL_CMD(2));
  TTCCAL2_RST_GEN : FD port map (Q => TTCCAL_RST(2), C => CMSCLK, D => TTCCAL_INNER(2));
  
  TTCCAL <= TTCCAL_INNER;
  
  -- generate BX0, BXRST, CLKENA, L1ARST latch
  BX0_IFD    : FD port map(Q => BX0_B,    C => CMSCLK, D => CCB_BX0_B);
  BXRST_IFD  : FD port map(Q => BXRST_B,  C => CMSCLK, D => CCB_BXRST_B);
  CLKEN_IFD  : FD port map(Q => CLKEN_B,  C => CMSCLK, D => CCB_CLKEN);
  L1ARST_IFD : FD port map(Q => L1ARST_B, C => CMSCLK, D => CCB_L1ARST_B);

  BX0    <= not BX0_B;
  BXRST  <= not BXRST_B;
  CLKEN  <= not CLKEN_B;
  L1ARST <= not L1ARST_B;

end CCBCODE_arch;
