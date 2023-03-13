library ieee;
library work;
library UNISIM;
use UNISIM.vcomponents.all;
use work.Latches_Flipflops.all;
use ieee.std_logic_1164.all;
use work.ucsb_types.all;


entity CONFREGS_DUMMY is
  port (
    SLOWCLK              : in std_logic;
    DEVICE               : in std_logic;
    STROBE               : in std_logic;
    COMMAND              : in std_logic_vector(9 downto 0);
    OUTDATA              : out std_logic_vector(15 downto 0);
    DTACK                : out std_logic;
    LCT_L1A_DLY          : out std_logic_vector(5 downto 0);
    INJ_DLY              : out std_logic_vector(4 downto 0);
    EXT_DLY              : out std_logic_vector(4 downto 0);
    CALLCT_DLY           : out std_logic_vector(3 downto 0);
    CABLE_DLY            : out integer range 0 to 1
    );
end CONFREGS_DUMMY;

architecture CONFREGS_DUMMY_Arch of CONFREGS_DUMMY is

  signal cmddev : std_logic_vector(15 downto 0);
  signal gen_output : std_logic := '0';
  signal read_output : std_logic := '0';
  signal d_dtack : std_logic := '0';

begin

  --output 0d3b when given VME command 4100
  cmddev <= "000" & DEVICE & COMMAND & "00";
  gen_output <= '1' when cmddev = x"1100" else '0';
  read_output <= STROBE and gen_output;
  OUTDATA(15 downto 0) <= x"0d3b" when (read_output = '1') else "ZZZZZZZZZZZZZZZZ";
  d_dtack <= '1' when (read_output = '1') else '0';
  FD_dtack : FD port map(D => d_dtack, C => SLOWCLK, Q => DTACK);

  --hardwire DLY registers
  LCT_L1A_DLY <= "011001";
  INJ_DLY <= "01000"; --what is normal value?
  EXT_DLY <= "01000"; --what is normal value?
  CALLCT_DLY <= "0100"; --what is normal value?
  CABLE_DLY <= 1; --what is normal value?

end CONFREGS_DUMMY_Arch;
