--Entity that simulates an LVMB on the KCU105 testbench for the ODMB7/5

library ieee;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_1164.all;

library unisim;
use unisim.vcomponents.all;

entity LVMB is
  generic (
    NFEB : integer range 1 to 7 := 7    -- Number of DCFEBS
    );  
  port (
    RST : in std_logic;

    LVMB_SCLK     : in  std_logic;
    LVMB_SDIN     : in  std_logic;
    LVMB_SDOUT_P  : out std_logic;
    LVMB_SDOUT_N  : out std_logic;
    LVMB_CSB      : in std_Logic_vector((NFEB-1) downto 0);
    LVMB_PON      : in std_Logic_vector(NFEB downto 0);
    MON_LVMB_PON  : out std_Logic_vector(NFEB downto 0);
    PON_LOAD_B    : in std_logic;
    PON_OE        : in std_logic
    );
end LVMB;

architecture LVMB_ARCH of LVMB is

  component LVMB_ADC is
    port (
      scl    : in    std_logic;
      sdi    : in    std_logic;
      sdo    : inout std_logic;
      ce     : in    std_logic;
      rst    : in    std_logic;
      device : in    std_logic_vector(3 downto 0)
      );
  end component;

  type     adc_addr_type is array (1 to NFEB) of std_logic_vector(3 downto 0);
  constant adc_addr   : adc_addr_type := (x"1", x"2", x"3", x"4", x"5", x"6", x"7");
  signal sim_lvmb_sdo : std_logic_vector(NFEB downto 1);
  signal lvmb_sdout   : std_logic;
  signal pon_status   : std_logic_vector(NFEB downto 0) := (others => '0');

begin

  --handle PON
  pon_status <= LVMB_PON when (PON_OE = '1' and PON_LOAD_B = '0') else
                pon_status;
  MON_LVMB_PON <= pon_status;

  --send ADC input to simulated ADCs
  GEN_ADC : for ind in NFEB downto 1 generate
  begin
    LVMB_ADC_PM : LVMB_ADC
      port map (
        scl    => LVMB_SCLK,
        sdi    => LVMB_SDIN,
        sdo    => sim_lvmb_sdo(ind),
        ce     => LVMB_CSB(ind-1),
        rst    => RST,
        device => adc_addr(ind));
  end generate GEN_ADC;

  --handle ADC output
  lvmb_sdout <= sim_lvmb_sdo(1) when LVMB_CSB = "1111110" else
                      sim_lvmb_sdo(2) when LVMB_CSB = "1111101" else
                      sim_lvmb_sdo(3) when LVMB_CSB = "1111011" else
                      sim_lvmb_sdo(4) when LVMB_CSB = "1110111" else
                      sim_lvmb_sdo(5) when LVMB_CSB = "1101111" else
                      sim_lvmb_sdo(6) when LVMB_CSB = "1011111" else
                      sim_lvmb_sdo(7) when LVMB_CSB = "0111111" else
                      '0';

  IB_LVMB_SDOUT: OBUFDS port map (I => lvmb_sdout, O => LVMB_SDOUT_P, OB => LVMB_SDOUT_N);
  
end LVMB_ARCH;
