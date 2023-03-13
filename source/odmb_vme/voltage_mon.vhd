-- WOrk for MAX1271B
-- https://datasheets.maximintegrated.com/en/ds/MAX1270-MAX1271B.pdf

library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_misc.all;
use ieee.std_logic_unsigned.all;

library unisim;
use unisim.vcomponents.all;

--! @brief module implementing SPI interface to MAX1271B chips
entity voltage_mon is
  port (
    CLK      : in  std_logic;                             --! 1.25MHz clock
    -- CLK_div2 : in  std_logic;
    CS       : out std_logic;                             --! SPI chip select to ADCs
    DIN      : out std_logic;                             --! SPI input to ADCs
    SCK      : out std_logic;                             --! SPI clock to ADCs
    DOUT     : in  std_logic;                             --! SPI output from ADCs
    DVOUT    : out std_logic;                             --! output data to fw valid
    DATADONE : out std_logic;                             --! indicates data retrieved from ADCs
    DATA     : out std_logic_vector(11 downto 0);         --! output data to fw
    DATAVALIDCNTR     : out std_logic_vector(7 downto 0); --! counts bits of data received; debug signal
    CURRENTCHANNELOUT : out std_logic_vector(2 downto 0); --! current channel being read; debug signal
    CTRLSEQDONE       : out std_logic;                    --! indicates control sequence has been sent; debug signal
    startchannelvalid : in std_logic                      --! begins an ADC read
    );
end voltage_mon;

architecture voltage_mon_arch of voltage_mon is

  signal current_channel : std_logic_vector(2 downto 0) := "000";
  signal mon_SpiCsB : std_logic := '1';
  signal SpiCsB_N        : std_logic;
  signal mon_start : std_logic := '0';
  signal mon_cmdcounter  : std_logic_vector(7 downto 0) := x"00";
  signal mon_cmdreg  : std_logic_vector(7 downto 0) := x"00";
  signal mon_inprogress  : std_logic := '0';
  signal ctrlseq_done : std_logic := '0';
  signal data_done : std_logic := '0';
  signal data_valid : std_logic := '0';
  signal data_valid_cntr : std_logic_vector(7 downto 0) := x"00";
  signal dout_data : std_logic_vector(11 downto 0) := x"000";
  signal dout_counter: std_logic_vector(7 downto 0) := x"00";
  signal variousflags: std_logic_vector(7 downto 0) := x"00";
  signal ila_trigger1: std_logic_vector(7 downto 0) := x"00";

  -- check table 1 of datasheet
  constant START  : std_logic := '1';
  constant STARTCHANNEL  : std_logic_vector(2 downto 0) := "000"; -- 3 bits for 8-channel selection
  constant RNG : std_logic := '1';
  constant BIP : std_logic := '0';
  constant PD1 : std_logic := '0';
  constant PD0 : std_logic := '1';

  type monstates is
    (S_MON_IDLE, S_MON_ASSCS1, S_MON_CTRLSEQ, S_MON_WAIT);
  signal monstate  : monstates := S_MON_IDLE;

  type doutstates is
    (S_DOUT_IDLE, S_DOUT_WAIT, S_DOUT_DATA);
  signal doutstate  : doutstates := S_DOUT_IDLE;

begin

  SCK <= CLK;
  DIN <= mon_cmdreg(7);
  CS <= SpiCsB_N;
  DATA <= dout_data;
  DATADONE <= data_done;
  DATAVALIDCNTR <= data_valid_cntr;
  CURRENTCHANNELOUT <= current_channel;
  CTRLSEQDONE <= ctrlseq_done;

  processmon : process (CLK)
  begin
    -- this part only controls sending ctrl sequence
    if rising_edge(CLK) then
      case monstate is
        when S_MON_IDLE =>
          mon_SpiCsB <= '1';
          ctrlseq_done <= '0';
          if (startchannelvalid = '1') then
            mon_start <= '1';
            current_channel <= STARTCHANNEL;
            mon_inprogress <= '1';
            monstate <= S_MON_ASSCS1;
          end if;
        -- send 8 bits control sequence
        when S_MON_ASSCS1 =>
          mon_SpiCsB <= '0';
          mon_cmdcounter <= x"11";  -- 18 clks conversion
          mon_cmdreg <=  START & current_channel & RNG & BIP & PD1 & PD0;
          monstate <= S_MON_CTRLSEQ;

        when S_MON_CTRLSEQ =>
          if (mon_cmdcounter > 10) then mon_cmdcounter <= mon_cmdcounter - 1;
                                        mon_cmdreg <= mon_cmdreg(6 downto 0) & '0';
          elsif (mon_cmdcounter > 1) then
            mon_cmdcounter <= mon_cmdcounter - 1;
            mon_cmdreg <= x"00";
          else
            -- all 7 channels finished
            if (current_channel = "111") then
              current_channel <= STARTCHANNEL;
              monstate <= S_MON_WAIT;
              mon_inprogress <= '0';
              mon_start <= '0';
              ctrlseq_done <= '1';
            else
              current_channel <= current_channel + 1;
              monstate <= S_MON_ASSCS1;
            end if;
          end if;

        -- wait for data finish
        when S_MON_WAIT =>
          if (data_done = '1') then
            monstate <= S_MON_IDLE;
          end if;
      end case;
    end if;  -- Clk
  end process processmon;

----
  processdout : process (CLK)
  begin
    -- this part only takes care of get data from dout
    if rising_edge(CLK) then
      case doutstate is
        when S_DOUT_IDLE =>

          dout_counter <= x"0c";  -- 18 clks conversion, after cs goes low for 13 clk, data starts to arrive
          data_done <= '0';
          data_valid_cntr <= x"11";
          data_valid <= '0';
          if (mon_start = '1') then
            doutstate <= S_DOUT_WAIT;
          end if;

        when S_DOUT_WAIT =>
          if (dout_counter /= 0) then
            dout_counter <= dout_counter - 1;
          else
            doutstate <= S_DOUT_DATA;
          end if;

        when S_DOUT_DATA =>
          data_valid_cntr <= data_valid_cntr - 1;
          --if (data_valid_cntr > 5 ) then -- 12 bits of valid data
          if (data_valid_cntr > 4 ) then -- 12 bits of valid data
            dout_data <= dout_data(10 downto 0) & DOUT;
            data_valid <= '0';
            --if (data_valid_cntr = 6) then
            if (data_valid_cntr = 5) then
              data_valid <= '1';
            end if;
          else
            data_valid <= '0';
            dout_data <= x"000";
            if (ctrlseq_done = '1') then
              doutstate <= S_DOUT_IDLE;
              data_done <= '1';
            else
              if (data_valid_cntr = 0) then
                data_valid_cntr <= x"11";
              end if;
            end if;  -- if ctrl sequence is done
          end if;
      end case;
    end if;  -- Clk
  end process processdout;

  DVOUT <= data_valid;

  negedgecs_flop : process (CLK)
  begin
    if falling_edge(CLK) then
      SpiCsB_N <= mon_SpiCsB;
    end if;
  end process;

end voltage_mon_arch;
