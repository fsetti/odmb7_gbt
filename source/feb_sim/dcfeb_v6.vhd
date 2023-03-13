-- DCFEB_V6: Simulates dummy DCFEBs, both data and JTAG behavior

library ieee;
library unisim;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use unisim.vcomponents.all;

entity dcfeb_v6 is
  generic (
    dcfeb_addr : std_logic_vector(3 downto 0) := "1000"  -- DCFEB address
    );  
  port (
    clk          : in std_logic;
    dcfebclk     : in std_logic;
    rst          : in std_logic;
    l1a          : in std_logic;
    l1a_match    : in std_logic;
    tx_ack       : in std_logic;
    nwords_dummy : in std_logic_vector(15 downto 0);

    dcfeb_dv      : out std_logic;
    dcfeb_data    : out std_logic_vector(15 downto 0);
    adc_mask      : out std_logic_vector(11 downto 0);
    dcfeb_fsel    : out std_logic_vector(63 downto 0);
    dcfeb_jtag_ir : out std_logic_vector(9 downto 0);
    trst          : in  std_logic;
    tck           : in  std_logic;
    tms           : in  std_logic;
    tdi           : in  std_logic;
    tdo           : out std_logic;
    rtn_shft_en   : out std_logic;
    done          : out std_logic;
    INJPLS        : in std_logic;
    EXTPLS        : in std_logic;
    BC0           : in std_logic;
    RESYNC        : in std_logic;
    DIAGOUT       : out std_logic_vector(17 downto 0));
end dcfeb_v6;


architecture dcfeb_v6_arch of dcfeb_v6 is

  component dcfeb_data_gen is
    port(
      clk          : in std_logic;
      dcfebclk     : in std_logic;
      rst          : in std_logic;
      l1a          : in std_logic;
      l1a_match    : in std_logic;
      tx_ack       : in std_logic;
      dcfeb_addr   : in std_logic_vector(3 downto 0);
      nwords_dummy : in std_logic_vector(15 downto 0);

      dcfeb_dv   : out std_logic;
      dcfeb_data : out std_logic_vector(15 downto 0)
      );
  end component;

  component tdo_mux
    port(
      TDO_0C : in  std_ulogic;
      TDO_17 : in  std_ulogic;
      TDO_3B3C : in std_ulogic;
      FSEL   : in  std_logic_vector(63 downto 0);
      TDO    : out std_ulogic
      );
  end component;

  component BGB_BSCAN_emulator is
    port(
      IR : out std_logic_vector(9 downto 0);

      CAPTURE1 : out std_ulogic;
      DRCK1_EN : out std_ulogic;
      RESET1   : out std_ulogic;
      SEL1     : out std_ulogic;
      SHIFT1   : out std_ulogic;
      UPDATE1  : out std_ulogic;
      RUNTEST1 : out std_ulogic;
      TDO1     : in  std_ulogic;

      CAPTURE2 : out std_ulogic;
      DRCK2_EN : out std_ulogic;
      RESET2   : out std_ulogic;
      SEL2     : out std_ulogic;
      SHIFT2   : out std_ulogic;
      UPDATE2  : out std_ulogic;
      RUNTEST2 : out std_ulogic;
      TDO2     : in  std_ulogic;

      TDO3 : in std_ulogic;
      TDO4 : in std_ulogic;

      TDO : out std_ulogic;

      TCK  : in std_ulogic;
      TDI  : in std_ulogic;
      TMS  : in std_ulogic;
      TRST : in std_ulogic
      );
  end component;

  component instr_dcd is
    port(
      TCK     : in  std_ulogic;
      DRCK_EN : in  std_ulogic;
      SEL     : in  std_ulogic;
      TDI     : in  std_ulogic;
      UPDATE  : in  std_ulogic;
      SHIFT   : in  std_ulogic;
      RST     : in  std_ulogic;
      CLR     : in  std_ulogic;
      F       : out std_logic_vector (63 downto 0);
      TDO     : out std_ulogic
      );
  end component;

  component user_wr_reg is
    generic (
      width     : integer                        := 12;
      def_value : std_logic_vector (11 downto 0) := "111111111111"
      );
    port (
      TCK       : in  std_ulogic;
      DRCK_EN   : in  std_ulogic;
      FSEL      : in  std_ulogic;
      SEL       : in  std_ulogic;
      TDI       : in  std_ulogic;
      DSY_IN    : in  std_ulogic;
      SHIFT     : in  std_ulogic;
      UPDATE    : in  std_ulogic;
      RST       : in  std_ulogic;
      DSY_CHAIN : in  std_ulogic;
      PO        : out std_logic_vector (width-1 downto 0);
      TDO       : out std_ulogic;
      DSY_OUT   : out std_ulogic
      );    
  end component;

  component user_cap_reg is
    generic (
      width : integer := 16
      );
    port (
      TCK     : in  std_ulogic;
      DRCK_EN : in  std_ulogic;
      FSH     : in  std_ulogic;
      FCAP    : in  std_ulogic;
      SEL     : in  std_ulogic;
      TDI     : in  std_ulogic;
      SHIFT   : in  std_ulogic;
      CAPTURE : in  std_ulogic;
      RST     : in  std_ulogic;
      PI      : in  std_logic_vector (width-1 downto 0);
      TDO     : out std_ulogic
      );      
  end component;
  
  component user_counter_reg is
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
    L1A_MATCH_COUNTER : in unsigned(11 downto 0); --L1A MATCH counter
    TDO : out std_logic      --Serial test data out
    );
  end component;



  signal fsel                                           : std_logic_vector(63 downto 0);
  signal bpi_status                                     : std_logic_vector(15 downto 0);
  signal int_adc_mask                                   : std_logic_vector(11 downto 0);
  signal drck1_en, sel1, reset1, shift1, capture1, update1 : std_logic;
  signal drck2_en, sel2, reset2, shift2, capture2, update2 : std_logic;
  signal tdo_f0c, tdo_f17, tdo_f3a3b3c3d                : std_logic;
  signal tdo1                                           : std_logic;
  signal tdo2                                           : std_logic;
  signal tdo3                                           : std_logic := '0';
  signal tdo4                                           : std_logic := '0';

  --signals for counting pulses
  signal injpls_prev, extpls_prev, bc0_prev, l1a_match_prev       : std_logic := '0';
  signal injpls_counter, extpls_counter, bc0_counter, l1a_match_counter : unsigned(11 downto 0) := (others=>'0');

begin

  dcfeb_fsel <= fsel;
  done <= '1'; 
  --always configured

  --handle pulse inputs in top level
  --on KCU, just use P lines as signals
 
  --count pulses
  pulse_counter : process (RESYNC, CLK)
  begin
    if RESYNC='1' then
      l1a_match_counter <= x"000";
      injpls_counter <= x"000";
      extpls_counter <= x"000";
      bc0_counter <= x"000";
    elsif CLK'event and CLK='1' then
      if INJPLS='1' and injpls_prev='0' then
        injpls_counter <= injpls_counter + 1;
      end if;
      if EXTPLS='1' and extpls_prev='0' then
        extpls_counter <= extpls_counter + 1;
      end if;
      if BC0='1' and bc0_prev='0' then
        bc0_counter <= bc0_counter + 1;
      end if;
      if L1A_MATCH='1' and l1a_match_prev='0' then
        l1a_match_counter <= l1a_match_counter + 1;
      end if;
      injpls_prev <= INJPLS;
      extpls_prev <= EXTPLS;
      bc0_prev <= BC0;
      l1a_match_prev <= L1A_MATCH;
    end if;
  end process;
  
  --debugging
  DIAGOUT(11 downto 0) <= std_logic_vector(extpls_counter);
  DIAGOUT(17 downto 12) <= "000000";

  --currently not using data-generation functionality
  PMAP_dcfeb_data_gen : dcfeb_data_gen
    port map(
      clk          => clk,
      dcfebclk     => dcfebclk,
      rst          => rst,
      l1a          => l1a,
      l1a_match    => l1a_match,
      tx_ack       => tx_ack,
      dcfeb_addr   => dcfeb_addr,
      nwords_dummy => nwords_dummy,

      dcfeb_dv   => dcfeb_dv,
      dcfeb_data => dcfeb_data
      );

  PMAP_BSCAN : BGB_BSCAN_emulator
    port map (
      IR => dcfeb_jtag_ir,

      CAPTURE1 => capture1,
      DRCK1_EN => drck1_en,
      RESET1   => reset1,
      SEL1     => sel1,
      SHIFT1   => shift1,
      UPDATE1  => update1,
      RUNTEST1 => open,
      TDO1     => tdo1,

      CAPTURE2 => capture2,
      DRCK2_EN => drck2_en,
      RESET2   => reset2,
      SEL2     => sel2,
      SHIFT2   => shift2,
      UPDATE2  => update2,
      RUNTEST2 => open,
      TDO2     => tdo2,

      TDO3 => tdo3,
      TDO4 => tdo4,

      TCK  => tck,
      TDI  => tdi,
      TMS  => tms,
      TDO  => tdo,
      TRST => trst
      );

  rtn_shft_en <= shift2;

  PMAP_INSTR_DECODER : instr_dcd
    port map (
      TCK     => tck,                    -- in
      DRCK_EN => drck1_en,                  -- in 
      SEL     => sel1,                   -- in 
      TDI     => tdi,                    -- in 
      UPDATE  => update1,                -- in 
      SHIFT   => shift1,                 -- in
      RST     => reset1,                 -- in  
      CLR     => '0',                    -- in
      F       => fsel,                   -- out
      TDO     => tdo1                    -- out
      );

  PMAP_TDO_MUX : tdo_mux
    port map(

      TDO_0C => tdo_f0c,                -- in
      TDO_17 => tdo_f17,                -- in
      TDO_3B3C => tdo_f3a3b3c3d,
      FSEL   => fsel,
      TDO    => tdo2
      );


  PMAP_ADC_MASK : user_wr_reg           -- #(.width(12), .def_value(12'hFFF))
--  generic map (
--     width => 12,
--     def_value => "111111111111"
--  );
    port map (
      TCK       => tck,                 -- in
      DRCK_EN   => drck2_en,            -- in
      FSEL      => fsel(12),            -- in
      SEL       => sel2,                -- in
      TDI       => tdi,                 -- in
      DSY_IN    => '0',                 -- in (not used)
      SHIFT     => shift2,              -- in
      UPDATE    => update2,             -- in
      RST       => reset2,              -- in
      DSY_CHAIN => '0',                 -- in (not used)
      PO        => adc_mask,            -- out
      TDO       => tdo_f0c,             -- out
      DSY_OUT   => open                 -- out (not used)
      );    

-- bgb
-- bgb put the value of adc_mask into bpi_status register for read back
-- bgb

-- Guido
-- bpi_status <= x"B" & int_adc_mask;
-- adc_mask <= int_adc_mask;
  bpi_status <= x"fede";

  PMAP_BPI_STATUS : user_cap_reg        -- #(.width(16))
--  generic map (
--     width => 16
--  );
    port map (
      TCK     => tck,                   -- in
      DRCK_EN => drck2_en,              -- in
      FSH     => '0',                   -- in (not used)
      FCAP    => fsel(23),              -- in
      SEL     => sel2,                  -- in
      TDI     => tdi,                   -- in
      SHIFT   => shift2,                -- in
      CAPTURE => capture2,              -- in
      RST     => reset2,                -- in
      PI      => bpi_status,            -- in
      TDO     => tdo_f17                -- in
      );      

  PMAP_COUNTERS : user_counter_reg
  port map (
    TCK       => tck,
    DRCK_EN   => drck2_en,
    FSEL_3A   => fsel(58),
    FSEL_3B   => fsel(59),
    FSEL_3C   => fsel(60),
    FSEL_3D   => fsel(61),
    SEL       => sel2,
    TDI       => TDI,
    SHIFT     => shift2,
    CAPTURE   => capture2,
    RST       => reset2,
    INJPLS_COUNTER => injpls_counter,
    EXTPLS_COUNTER => extpls_counter,
    BC0_COUNTER => bc0_counter,
    L1A_MATCH_COUNTER => l1a_match_counter,
    TDO       => tdo_f3a3b3c3d
    );


end dcfeb_v6_arch;
