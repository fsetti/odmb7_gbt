library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_misc.all;

library unisim;
use unisim.vcomponents.all;

--! @brief ODMB7 clock management module
entity odmb_clocking is
  port (
    --------------------
    -- Input ports
    --------------------
    CMS_CLK_FPGA_P : in std_logic;      --! system clock: 40.07897 MHz
    CMS_CLK_FPGA_N : in std_logic;      --! system clock: 40.07897 MHz
    GP_CLK_6_P : in std_logic;          --! clock synthesizer ODIV6: 80 MHz
    GP_CLK_6_N : in std_logic;          --! clock synthesizer ODIV6: 80 MHz
    GP_CLK_7_P : in std_logic;          --! clock synthesizer ODIV7: 80 MHz
    GP_CLK_7_N : in std_logic;          --! clock synthesizer ODIV7: 80 MHz
    REF_CLK_1_P : in std_logic;         --! refclk0 to MGT quad 224
    REF_CLK_1_N : in std_logic;         --! refclk0 to MGT quad 224
    REF_CLK_2_P : in std_logic;         --! refclk0 to MGT quad 227
    REF_CLK_2_N : in std_logic;         --! refclk0 to MGT quad 227
    REF_CLK_3_P : in std_logic;         --! refclk0 to MGT quad 226
    REF_CLK_3_N : in std_logic;         --! refclk0 to MGT quad 226
    REF_CLK_4_P : in std_logic;         --! refclk0 to MGT quad 225
    REF_CLK_4_N : in std_logic;         --! refclk0 to MGT quad 225
    REF_CLK_5_P : in std_logic;         --! refclk1 to MGT quad 227
    REF_CLK_5_N : in std_logic;         --! refclk1 to MGT quad 227
    CLK_125_REF_P : in std_logic;       --! refclk1 to MGT quad 226
    CLK_125_REF_N : in std_logic;       --! refclk1 to MGT quad 226
    LF_CLK : in std_logic;              --! Low frequency, 10 kHz

    --------------------
    -- Output clocks
    --------------------
    mgtrefclk0_224 : out std_logic;     --! buffered refclk0 for MGT quad 224
    mgtrefclk0_225 : out std_logic;     --! buffered refclk0 for MGT quad 225
    mgtrefclk0_226 : out std_logic;     --! buffered refclk0 for MGT quad 226
    mgtrefclk1_226 : out std_logic;     --! buffered refclk1 for MGT quad 226
    mgtrefclk0_227 : out std_logic;     --! buffered refclk0 for MGT quad 227
    mgtrefclk1_227 : out std_logic;     --! buffered refclk1 for MGT quad 227

    clk_sysclk625k : out std_logic;     --! buffered 625 kHz clock
    clk_sysclk1p25 : out std_logic;     --! buffered 1.25 MHz clock
    clk_sysclk2p5 : out std_logic;      --! buffered 2.5 MHz clock
    clk_sysclk10 : out std_logic;       --! buffered 10 MHz clock
    clk_sysclk20 : out std_logic;       --! buffered 20 MHz clock
    clk_sysclk40 : out std_logic;       --! buffered 40 MHz clock
    clk_sysclk80 : out std_logic;       --! buffered 80 MHz clock
    clk_cmsclk : out std_logic;         --! buffered CMS (40.07897 MHz) clock
    clk_lfclk : out std_logic;          --! buffered 10 kHz clock
    clk_gp6 : out std_logic;            --! buffered 80 MHz cock
    clk_gp7 : out std_logic;            --! buffered 80 MHz clock
 
    clk_mgtclk1 : out std_logic;        --! buffered clock from MGT quad 224 clock 0 divided by 2
    clk_mgtclk2 : out std_logic;        --! buffered clock from MGT quad 227 clock 0 divided by 2
    clk_mgtclk3 : out std_logic;        --! buffered clock from MGT quad 226 clock 0 divided by 2
    clk_mgtclk4 : out std_logic;        --! buffered clock from MGT quad 225 clock 0 divided by 2
    clk_mgtclk5 : out std_logic;        --! buffered clock from MGT quad 227 clock 1 divided by 2
    clk_mgtclk125 : out std_logic       --! buffered clock from MGT quad 226 clock 1 divided by 2

    );
end odmb_clocking;

architecture Clocking_Arch of odmb_clocking is

  component clockManager is
    port (
      clk_in1   : in std_logic;
      clk_out5  : out std_logic;
      clk_out10 : out std_logic;
      clk_out20 : out std_logic;
      clk_out40 : out std_logic;
      clk_out80 : out std_logic
      );
  end component;

  signal mgtrefclk0_224_odiv2 : std_logic;
  signal mgtrefclk0_225_odiv2 : std_logic;
  signal mgtrefclk0_226_odiv2 : std_logic;
  signal mgtrefclk1_226_odiv2 : std_logic;
  signal mgtrefclk0_227_odiv2 : std_logic;
  signal mgtrefclk1_227_odiv2 : std_logic;

  signal clk_sysclk5 : std_logic;
  signal clk2p5_unbuf : std_logic := '0';
  signal clk1p25_unbuf : std_logic := '0';
  signal clk625k_unbuf : std_logic := '0';
  signal clk2p5_inv : std_logic := '1';
  signal clk1p25_inv : std_logic := '1';
  signal clk625k_inv : std_logic := '1';

  signal clk_cmsclk_unbuf : std_logic;
  signal clk_gp6_unbuf : std_logic;
  signal clk_gp7_unbuf : std_logic;

begin

  ------------------------------------------
  -- Differential input buffers for clocks
  ------------------------------------------

  -- Special IBUF for MGT reference clocks
  u_buf_gth_q0_clk0 : IBUFDS_GTE3
    port map (
      O     => mgtrefclk0_224,
      ODIV2 => mgtrefclk0_224_odiv2,
      CEB   => '0',
      I     => REF_CLK_1_P,
      IB    => REF_CLK_1_N
      );

  u_buf_gth_q1_clk0 : IBUFDS_GTE3
    port map (
      O     => mgtrefclk0_225,
      ODIV2 => mgtrefclk0_225_odiv2,
      CEB   => '0',
      I     => REF_CLK_4_P,
      IB    => REF_CLK_4_N
      );

  u_buf_gth_q2_clk0 : IBUFDS_GTE3
    port map (
      O     => mgtrefclk0_226,
      ODIV2 => mgtrefclk0_226_odiv2,
      CEB   => '0',
      I     => REF_CLK_3_P,
      IB    => REF_CLK_3_N
      );

  u_buf_gth_q2_clk1 : IBUFDS_GTE3
    port map (
      O     => mgtrefclk1_226,
      ODIV2 => mgtrefclk1_226_odiv2,
      CEB   => '0',
      I     => CLK_125_REF_P,
      IB    => CLK_125_REF_N
      );

  u_buf_gth_q3_clk0 : IBUFDS_GTE3
    port map (
      O     => mgtrefclk0_227,
      ODIV2 => mgtrefclk0_227_odiv2,
      CEB   => '0',
      I     => REF_CLK_2_P,
      IB    => REF_CLK_2_N
      );

  u_buf_gth_q3_clk1 : IBUFDS_GTE3
    port map (
      O     => mgtrefclk1_227,
      ODIV2 => mgtrefclk1_227_odiv2,
      CEB   => '0',
      I     => REF_CLK_5_P,
      IB    => REF_CLK_5_N
      );

  -- Special IBUF for other input clocks
  u_ibufgds_gp7 : IBUFGDS
    generic map (DIFF_TERM => TRUE)
    port map (
      I => GP_CLK_7_P,
      IB => GP_CLK_7_N,
      O => clk_gp7_unbuf
    );

  u_ibufgds_gp6 : IBUFGDS
    generic map (DIFF_TERM => TRUE)
    port map (
      I => GP_CLK_6_P,
      IB => GP_CLK_6_N,
      O => clk_gp6_unbuf
      );

  -- Using the clock manager output as IBERT sysclk <- option 2
  u_ibufgds_cms : IBUFGDS
    port map (
      I => CMS_CLK_FPGA_P,
      IB => CMS_CLK_FPGA_N,
      O => clk_cmsclk_unbuf
    );

  -- Adding BUFG to the clocks
  u_bufg_gp7 : BUFG port map (I => clk_gp7_unbuf, O => clk_gp7);
  u_bufg_gp6 : BUFG port map (I => clk_gp6_unbuf, O => clk_gp6);
  u_bufg_cms : BUFG port map (I => clk_cmsclk_unbuf, O => clk_cmsclk);
  u_bufg_lfc : BUFG port map (I => LF_CLK, O => clk_lfclk);

  -- BUFG for GT clocks
  u_mgtclk0_q224 : BUFG_GT
    port map(
      I       => mgtrefclk0_224_odiv2,
      O       => clk_mgtclk1,
      CE      => '1',
      CEMASK  => '0',
      CLR     => '0',
      CLRMASK => '0',
      DIV     => "000"
      );

  u_mgtclk0_q225 : BUFG_GT
    port map(
      I       => mgtrefclk0_225_odiv2,
      O       => clk_mgtclk4,
      CE      => '1',
      CEMASK  => '0',
      CLR     => '0',
      CLRMASK => '0',
      DIV     => "000"
      );

  u_mgtclk0_q226 : BUFG_GT
    port map(
      I       => mgtrefclk0_226_odiv2,
      O       => clk_mgtclk3,
      CE      => '1',
      CEMASK  => '0',
      CLR     => '0',
      CLRMASK => '0',
      DIV     => "000"
      );

  u_mgtclk1_q226 : BUFG_GT
    port map(
      I       => mgtrefclk1_226_odiv2,
      O       => clk_mgtclk125,
      CE      => '1',
      CEMASK  => '0',
      CLR     => '0',
      CLRMASK => '0',
      DIV     => "000"
      );

  u_mgtclk0_q227 : BUFG_GT
    port map(
      I       => mgtrefclk0_227_odiv2,
      O       => clk_mgtclk2,
      CE      => '1',
      CEMASK  => '0',
      CLR     => '0',
      CLRMASK => '0',
      DIV     => "000"
      );

  u_mgtclk1_q227 : BUFG_GT
    port map(
      I       => mgtrefclk1_227_odiv2,
      O       => clk_mgtclk5,
      CE      => '1',
      CEMASK  => '0',
      CLR     => '0',
      CLRMASK => '0',
      DIV     => "000"
      );

  clockManager_i : clockManager
    port map (
      clk_in1   => clk_cmsclk_unbuf, -- input  40 MHz
      clk_out5  => clk_sysclk5,      -- output  5 MHz
      clk_out10 => clk_sysclk10,     -- output 10 MHz
      clk_out20 => clk_sysclk20,     -- output 20 MHz
      clk_out40 => clk_sysclk40,     -- output 40 MHz
      clk_out80 => clk_sysclk80      -- output 80 MHz
      );


  -------------------------------------------------------------------------------------------
  -- Handle clock synthesizer signals and generate clocks
  -------------------------------------------------------------------------------------------
  -- In first version of test firmware, we will want to generate everything from 40 MHz cms clock, likely with Clock Manager IP
  -- Generate lower frequency clocks by FD
  clk2p5_inv <= not clk2p5_unbuf;
  clk1p25_inv <= not clk1p25_unbuf;
  clk625k_inv <= not clk625k_unbuf;
  FD_clk2p5 : FD port map(D => clk2p5_inv, C => clk_sysclk5, Q => clk2p5_unbuf);
  FD_clk1p25 : FD port map(D => clk1p25_inv, C => clk2p5_unbuf, Q => clk1p25_unbuf);
  FD_clk625k : FD port map(D => clk625k_inv, C => clk1p25_unbuf, Q => clk625k_unbuf);
  BUFG_clk2p5 : BUFG port map(I => clk2p5_unbuf, O => clk_sysclk2p5);
  BUFG_clk1p25 : BUFG port map(I => clk1p25_unbuf, O => clk_sysclk1p25);
  BUFG_clk625k : BUFG port map(I => clk625k_unbuf, O => clk_sysclk625k);

end Clocking_Arch;
