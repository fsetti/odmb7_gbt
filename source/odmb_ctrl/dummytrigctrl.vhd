-- CALIBTRG: Generates EXTPLS, INJPLS, and L1A_MATCHes that fake muons for
-- calibration purposes.

library ieee;
library work;
library UNISIM;
use UNISIM.vcomponents.all;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.std_logic_arith.all;
use ieee.numeric_std.all;
use work.ucsb_types.all;

entity DUMMY_TRIGCTRL is
  generic (
    NCFEB : integer range 1 to 7 := 7
    );
  port (
    CLK40       : in  std_logic;
    RAW_L1A     : in  std_logic;
    CAL_L1A     : in  std_logic;
    CAL_MODE    : in  std_logic;
    PEDESTAL    : in  std_logic;
    DCFEB_L1A   : out std_logic;
    DCFEB_L1A_MATCH : out std_logic_vector(NCFEB downto 1)
    );
end DUMMY_TRIGCTRL;

architecture DUMMY_TRIGCTRL_arch of DUMMY_TRIGCTRL is

  signal l1a, l1a_in                                     : std_logic := '0';
  signal l1a_match                                       : std_logic_vector(NCFEB downto 1) := (others => '0');

begin

  l1a_in <= CAL_L1A when CAL_MODE = '1' else RAW_L1A;
  FD_L1A : FD port map(Q => l1a, C => CLK40, D => l1a_in);
  DCFEB_L1A <= l1a;

  --dummy version just makes l1a matches when l1a pedestal is enabled
  l1a_match <= (others => '1') when (l1a='1' and PEDESTAL='1') else (others => '0');
  DCFEB_L1A_MATCH <= l1a_match;

end DUMMY_TRIGCTRL_arch;
