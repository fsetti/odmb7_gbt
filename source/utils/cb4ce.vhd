
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
entity CB4CE is
  port (
    C       : in  std_logic;
    CE      : in  std_logic;
    CLR     : in  std_logic;
    Q_in    : in std_logic_vector(3 downto 0);
    Q       : out std_logic_vector(3 downto 0);
    CEO     : out std_logic;
    TC      : out std_logic
    );
end CB4CE;

architecture Behavioral of CB4CE is

  signal COUNT : STD_LOGIC_VECTOR(3 downto 0) := (others => '0');
  constant TERMINAL_COUNT : STD_LOGIC_VECTOR(3 downto 0) := (others => '1');
  
begin

  process(C, CLR)
  begin
    if (CLR='1') then
      COUNT <= (others => '0');
    elsif (C'event and C = '1') then
      if (CE='1') then 
        COUNT <= COUNT+1;
      end if;
    end if;
  end process;

  TC  <=  '0' when (CLR = '1') else
          '1' when (COUNT = TERMINAL_COUNT) else '0';
  CEO <= '1' when ((COUNT = TERMINAL_COUNT) and CE='1') else '0';
  Q   <= COUNT;


end Behavioral;
