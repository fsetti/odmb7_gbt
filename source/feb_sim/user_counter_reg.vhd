library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library unisim;
use UNISIM.vcomponents.all;
--use UNISIM.vpck.all;
use UNISIM.all;

library unisim;
use unisim.Vcomponents.all;



entity user_counter_reg is

  port(

    TCK : in std_logic;       --TCK clock
    DRCK_EN : in std_logic;   --Data Reg Clock enable
    FSEL_3A : in std_logic;   --3A (L1AMATCH counter) function select
    FSEL_3B : in std_logic;   --3B (INJPLS counter) function select
    FSEL_3C : in std_logic;   --3C (EXTPLS counter) function select
    FSEL_3D : in std_logic;   --3D (BC0 counter) function select
    SEL : in std_logic;       --User mode active
    TDI : in std_logic;       --JTAG serial test data in
    SHIFT : in std_logic;     --Indicates JTAG (Data Register) shift state
    CAPTURE : in std_logic;   --Indicates JTAG (Data Register) capture state
    RST : in std_logic;       --Reset default state
    INJPLS_COUNTER : in unsigned(11 downto 0); --INJPLS counter
    EXTPLS_COUNTER : in unsigned(11 downto 0); --EXTPLS counter
    BC0_COUNTER : in unsigned(11 downto 0); --BC0 counter
    L1A_MATCH_COUNTER : in unsigned(11 downto 0); --L1AMATCH counter
    TDO : out std_logic      --Serial test data out
    );

end user_counter_reg;

architecture user_counter_reg_arch of user_counter_reg is

  signal d : std_logic_vector(11 downto 0) := (others=>'0');
  signal ce_l1amatch, ce_injpls, ce_extpls, ce_bc0 : std_logic := '0';

begin

  TDO <= (ce_injpls or ce_extpls or ce_l1amatch or ce_bc0) and d(0);
  ce_l1amatch <= SEL and DRCK_EN and FSEL_3A and (CAPTURE or SHIFT);
  ce_injpls <= SEL and DRCK_EN and FSEL_3B and (CAPTURE or SHIFT);
  ce_extpls <= SEL and DRCK_EN and FSEL_3C and (CAPTURE or SHIFT);
  ce_bc0 <= SEL and DRCK_EN and FSEL_3D and (CAPTURE or SHIFT);

  --d_shift_i : process (DRCK, RST, ce_injpls, ce_extpls, CAPTURE, SHIFT) is
  d_shift_i : process (TCK, RST) is
  begin
    if RST='1' then
      d <= x"000";
    else
      if rising_edge(TCK) then
        if ce_l1amatch='1' then
          if CAPTURE='1' then
            d <= std_logic_vector(L1A_MATCH_COUNTER);
          elsif SHIFT='1' then
            d <= TDI & d(11 downto 1);
          end if;
        elsif ce_injpls='1' then
          if CAPTURE='1' then
            d <= std_logic_vector(INJPLS_COUNTER);
          elsif SHIFT='1' then
            d <= TDI & d(11 downto 1);
          end if;
        elsif ce_extpls='1' then
          if CAPTURE='1' then
            d <= std_logic_vector(EXTPLS_COUNTER);
          elsif SHIFT='1' then
            d <= TDI & d(11 downto 1);
          end if;
        elsif ce_bc0='1' then
          if CAPTURE='1' then
            d <= std_logic_vector(BC0_COUNTER);
          elsif SHIFT='1' then
            d <= TDI & d(11 downto 1);
          end if;
        end if;
      end if;
    end if;
  end process;

end user_counter_reg_arch;
