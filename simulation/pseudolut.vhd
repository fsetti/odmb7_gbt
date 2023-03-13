Library UNISIM;
library ieee;
use UNISIM.vcomponents.all;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity pseudolut is
  port (
    CLK   : in std_logic;
    ADDR  : in std_logic_vector(3 downto 0);
    DOUT1 : out std_logic_vector(15 downto 0);
    DOUT2 : out std_logic_vector(15 downto 0)
  );
end pseudolut;

architecture behavioral of pseudolut is
  type lut_array is array (0 to 15) of std_logic_vector(15 downto 0);

  constant vme_addrs : lut_array := (x"4100", x"602C", x"602C", x"602C",
                                     x"602C", x"602C", x"6030", x"4100",
                                     x"4200", x"4300", x"4200", x"4200",
                                     x"4300", x"4100", x"4200", x"4300");
  constant vme_datas : lut_array := (x"2EAD", x"1FF7", x"0001", x"0033",
                                     x"0034", x"0035", x"2EAD", x"2EAD",
                                     x"2EAD", x"2EAD", x"2EAD", x"2EAD",
                                     x"2EAD", x"2EAD", x"2EAD", x"2EAD");

  signal dout1_inner : std_logic_vector(15 downto 0) := (others => '0');
  signal dout2_inner : std_logic_vector(15 downto 0) := (others => '0');

begin 
   
   proc_pseudolut : process (CLK)
   begin
     if rising_edge(CLK) then
       dout1_inner <= vme_addrs(to_integer(unsigned(ADDR)));
       dout2_inner <= vme_datas(to_integer(unsigned(ADDR)));
     end if;
   end process;

   DOUT1 <= dout1_inner;
   DOUT2 <= dout2_inner;

end behavioral;

