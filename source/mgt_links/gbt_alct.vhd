--------------------------------------------------------------------------------
-- MGT wrapper
-- Based on example design
--------------------------------------------------------------------------------

library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

library work;
use work.ucsb_types.all;

library UNISIM;
use UNISIM.VComponents.all;

use ieee.std_logic_misc.all;

entity gbt_alct is
  port (
    -- Clocks
    mgtrefclk   : in  std_logic;  --! Input MGT reference clock signal after buffer
    cmsclk      : in  std_logic;  --! Independent clock signal to drive for the helper block of the MGT IP, 80 MHz
    drpclk      : in  std_logic;  --! DRPCLK for the gtwizard module, 120.24 MHz derived from mgtrefclk0_225
    rxusrclk    : out std_logic;  --! The USRCLK signal for RX data readout 120.24 MHz
    rxclken     : out std_logic;  --! The clock enable signal for the RX data readout, 40.079 MHz, 1/3 duty cycle

    -- Serial data ports for transceiver at bank 224-225
    daq_rx_n    : in std_logic; --! Connected to differential optical input signals
    daq_rx_p    : in std_logic; --! Connected to differential optical input signals

    -- Receiver signals
    rxdata      : out std_logic_vector(71 downto 0); --! 4 words
    rxd_valid   : out std_logic; --! Flag for valid data
    bad_rx      : out std_logic; --! Flag for fiber errors
    --rxready     : out std_logic; --! Flag for rx reset done
    kill        : in  std_logic; --! Kill signal for ALCT readout

    -- -- Data FIFO full signals
    -- fifo_full   : in std_logic_vector(NLINK downto 1);    --! Flag for ALCT data FIFO full
    -- fifo_afull  : in std_logic_vector(NLINK downto 1);    --! Flag for ALCT data FIFO almost full

    -- Temporary for debug
    rxdata_remap : out std_logic_vector(111 downto 0);
    alct_mgt_rxready  : out std_logic; -- Flag for valid mgt status
    alct_gbt_rxready  : out std_logic; -- Flag for valid gbt sync status
    -- Reset
    reset        : in  std_logic;                          --! The Global reset signal
    rxdata_raw_gbt   : out std_logic_vector(83 downto 0);
    rxdata_raw_wb   : out std_logic_vector(31 downto 0);
    ila_data_mgt                    : out std_logic_vector(83 downto 0)
    );
end gbt_alct;

architecture Behavioral of gbt_alct is

  signal alct_rxusrclk     : std_logic; -- User clock for ALCT, at 120 MHz
  signal alct_rxclken      : std_logic; -- Clock enable signal, on for every third clock of the usrclk
  signal alct_rxdata_gbt   : std_logic_vector(83 downto 0);  -- Data received for GBT Frame
  signal alct_rxdata_wb    : std_logic_vector(31 downto 0);  -- Extra data for Wide Bus
  signal alct_rxdata_raw   : std_logic_vector(111 downto 0);
  signal alct_rxd_valid    : std_logic; -- Flag for valid data

  signal alct_rxready      : std_logic; -- Flag combined of previous two
  signal alct_bad_rx       : std_logic; -- Flag for bad receiver packet / fiber error

  signal alct_data_word    : t_std18_array(4 downto 0);
  signal alct_rxdata_pkt   : t_std14_array(7 downto 0);
  signal alct_halfword_reg : std_logic_vector(13 downto 0); -- latched for the last packet


  function extract_alct_word_from_frame (data  : std_logic_vector(111 downto 0);
                                         index : integer)
    return std_logic_vector is
  begin
    return (data(104 + index) & data(96 + index) & data(88 + index) & data(80 + index) &
            data( 72 + index) & data(64 + index) & data(56 + index) & data(48 + index) &
            data( 40 + index) & data(32 + index) & data(24 + index) & data(16 + index) &
            data(  8 + index) & data( 0 + index));
  end;

begin

  GBT_ALCT : entity work.gbt_wrapper
    generic map(
      NUM_LINKS         => 1,
      LINK_TYPE         => 0,   -- 0: ALCT, 1: BCK_PRS
      TX_ENCODING       => 1,   -- 0: GBT_FRAME, 1: WIDE_BUS, 2: GBT_DYNAMIC
      RX_ENCODING       => 1    -- 0: GBT_FRAME, 1: WIDE_BUS, 2: GBT_DYNAMIC
      )
    port map (

      --==============--
      -- Clocks       --
      --==============--
      MGT_REFCLK        => MGTREFCLK,      -- 120.24 MHz
      GBT_FRAMECLK      => CMSCLK,         -- 40.079 MHz
      MGT_DRP_CLK       => DRPCLK,         -- 120.24 MHz derived from mgtrefclk0_225

      GBT_TXUSRCLK_o(1) => open,
      GBT_RXUSRCLK_o(1) => alct_rxusrclk,
      GBT_TXCLKEN_o(1)  => open,           -- from pattern generator, to be evaluated
      GBT_RXCLKEN_o(1)  => alct_rxclken,   -- to pattern checker, to be evaluated

      --==============--
      -- Serial lanes --
      --==============--
      MGT_RX_P(1)       => DAQ_RX_P,
      MGT_RX_N(1)       => DAQ_RX_N,
      MGT_TX_P(1)       => open,
      MGT_TX_N(1)       => open,

      --==============--
      -- Data         --
      --==============--
      GBT_TXDATA_i(1)   => (others => '0'),
      GBT_RXDATA_o(1)   => alct_rxdata_gbt,
      WB_TXDATA_i(1)    => (others => '0'),
      WB_RXDATA_o(1)    => alct_rxdata_wb,

      TXD_VALID_i(1)    => '0',
      RXD_VALID_o(1)    => alct_rxd_valid,

      --==============--
      -- TX/RX Status --
      --==============--
      MGT_TXREADY_o(1)  => open,
      MGT_RXREADY_o(1)  => alct_mgt_rxready,
      GBT_TXREADY_o(1)  => open,
      GBT_RXREADY_o(1)  => alct_gbt_rxready,
      GBT_BAD_RX_o(1)   => BAD_RX,

      --==============--
      -- Reset        --
      --==============--
      RESET_i           => reset,
      
      
      ila_data_mgt  => ila_data_mgt
      );

  alct_rxdata_raw <= alct_rxdata_wb & alct_rxdata_gbt(79 downto 0);
  rxdata_raw_gbt    <= alct_rxdata_gbt;
  rxdata_raw_wb    <= alct_rxdata_wb;
  
  --alct_rxready <= alct_mgt_rxready and alct_gbt_rxready;

  rxdata_pkt_gen: for i in 0 to 7 generate
    alct_rxdata_pkt(i) <= extract_alct_word_from_frame(alct_rxdata_raw, i);
  end generate;

  alct_word_assemble : process (alct_rxusrclk, alct_rxclken)
  begin
    if (rising_edge(alct_rxusrclk) and alct_rxclken = '1') then
      if (alct_rxdata_pkt(0)(13) = '1') then
        alct_data_word(0) <= alct_rxdata_pkt(1)(8) & alct_rxdata_pkt(1)(6 downto 0) & alct_rxdata_pkt(0)(9 downto 0);
        alct_data_word(1) <= alct_rxdata_pkt(3)(8) & alct_rxdata_pkt(3)(6 downto 0) & alct_rxdata_pkt(2)(9 downto 0);
        alct_data_word(2) <= alct_rxdata_pkt(5)(8) & alct_rxdata_pkt(5)(6 downto 0) & alct_rxdata_pkt(4)(9 downto 0);
        alct_data_word(3) <= alct_rxdata_pkt(7)(8) & alct_rxdata_pkt(7)(6 downto 0) & alct_rxdata_pkt(6)(9 downto 0);
      else
        alct_data_word(0) <= alct_rxdata_pkt(0)(8) & alct_rxdata_pkt(0)(6 downto 0) & alct_halfword_reg(9 downto 0);
        alct_data_word(1) <= alct_rxdata_pkt(2)(8) & alct_rxdata_pkt(2)(6 downto 0) & alct_rxdata_pkt(1)(9 downto 0);
        alct_data_word(2) <= alct_rxdata_pkt(4)(8) & alct_rxdata_pkt(4)(6 downto 0) & alct_rxdata_pkt(3)(9 downto 0);
        alct_data_word(3) <= alct_rxdata_pkt(6)(8) & alct_rxdata_pkt(6)(6 downto 0) & alct_rxdata_pkt(5)(9 downto 0);
        alct_halfword_reg <= alct_rxdata_pkt(7);
      end if;
    end if;
  end process;

  RXDATA <= alct_data_word(3) & alct_data_word(2) & alct_data_word(1) & alct_data_word(0);

  RXUSRCLK <= alct_rxusrclk;
  RXCLKEN  <= alct_rxclken;
  --RXREADY  <= alct_rxready;
  RXD_VALID <= alct_rxd_valid;

  ---------------------------------------------------------------------------------------------------------------------
  -- Debugging
  ---------------------------------------------------------------------------------------------------------------------
  -- Connect debug signal for all channels

  RXDATA_REMAP <= alct_rxdata_pkt(7) & alct_rxdata_pkt(6) & alct_rxdata_pkt(5) & alct_rxdata_pkt(4) &
                  alct_rxdata_pkt(3) & alct_rxdata_pkt(2) & alct_rxdata_pkt(1) & alct_rxdata_pkt(0);

end Behavioral;
