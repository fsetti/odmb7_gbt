library ieee;
use ieee.std_logic_1164.all;
library unisim;
use unisim.vcomponents.all;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_misc.all;

--! @brief VME device controlling access to ODMB board monitoring (currents, voltages, temperature)
--! @details Supported VME commands:
--! * R 7XY0 read SYSMON channel XY (see below) - current is result*10 channels 0 and 9 and result*5 for others
--! * W 73Y0 load data from ADC chip Y (chip 0-4)
--! * R 74Y0 read loaded ADC for channel Y (channels 1-8) - number is voltage/1000
--! #Sysmon channels
--! 00 5V input current
--! 01 3.3V current 
--! 02 3.3V optical current
--! 03 3.3V clock current
--! 04 3.6V PPIB current
--! 05 2.5V current
--! 06 1.2V MGT current
--! 07 1.0V MGT current
--! 08 0.95V core current
--! 09 3.3V input current
--! 10 1.8V current
--! 11 1.8V VCC aux current
--! 12 1.8V MGT current
--! 13 1.8V VCCO current
--! 14 1.8V VCCO0_65 current
--! 15 1.8V clock current
entity SYSTEM_MON is
  port (
    OUTDATA   : out std_logic_vector(15 downto 0); --! Output data to VME backplane
    DTACK     : out std_logic;                     --! Data acknowledge to VME backplane

    ADC_CS_B  : out std_logic_vector(4 downto 0);  --! SPI chip select to ADCs
    ADC_DIN   : out std_logic;                     --! SPI input to ADCs
    ADC_SCK   : out std_logic;                     --! SPI clock to ADCs
    ADC_DOUT  : in std_logic;                      --! SPI output from ADCs

    SLOWCLK   : in std_logic;                      --! 1.25 MHz clock
    FASTCLK   : in std_logic;                      --! 40 MHz clock
    RST       : in std_logic;                      --! Soft reset
    DEVICE    : in std_logic;                      --! Indicates if this is the selected VME device
    STROBE    : in std_logic;                      --! Indicates VME command ready
    COMMAND   : in std_logic_vector(9 downto 0);   --! VME command
    WRITER    : in std_logic;                      --! Indicates if a command is read (1) or write (0)

    VAUXP     : in std_logic_vector(15 downto 0);  --! Current monitoring analog signals
    VAUXN     : in std_logic_vector(15 downto 0)   --! Current monitoring analog signals
    );
end SYSTEM_MON;

architecture SYSTEM_MON_ARCH of SYSTEM_MON is

  component oneshot is
    port (
      trigger: in  std_logic;
      clk : in std_logic;
      pulse: out std_logic
      );
  end component;

  component voltage_mon is
    port (
      CLK      : in  std_logic;
      CS       : out std_logic;
      DIN      : out std_logic;
      SCK      : out std_logic;
      DOUT     : in  std_logic;
      DVOUT    : out std_logic;
      DATADONE : out std_logic;
      DATA     : out std_logic_vector(11 downto 0);
      DATAVALIDCNTR     : out std_logic_vector(7 downto 0);
      CURRENTCHANNELOUT : out std_logic_vector(2 downto 0);
      CTRLSEQDONE       : out std_logic;

      startchannelvalid : in std_logic
      );
  end component;

  -- ILA instantiations to help debugging
  -- component ila_volMon is
  --   port (
  --     clk : in std_logic := '0';
  --     probe0 : in std_logic_vector(7 downto 0) := (others=> '0');
  --     probe1 : in std_logic_vector(15 downto 0) := (others=> '0');
  --     probe2 : in std_logic_vector(11 downto 0) := (others=> '0');
  --     probe3 : in std_logic_vector(11 downto 0) := (others=> '0');
  --     probe4 : in std_logic_vector(7 downto 0) := (others=> '0');
  --     probe5 : in std_logic_vector(11 downto 0) := (others=> '0');
  --     probe6 : in std_logic_vector(11 downto 0) := (others=> '0');
  --     probe7 : in std_logic_vector(11 downto 0) := (others=> '0');
  --     probe8 : in std_logic_vector(11 downto 0) := (others=> '0');
  --     probe9 : in std_logic_vector(11 downto 0) := (others=> '0');
  --     probe10 : in std_logic_vector(11 downto 0) := (others=> '0');
  --     probe11 : in std_logic_vector(11 downto 0) := (others=> '0');
  --     probe12 : in std_logic_vector(11 downto 0) := (others=> '0');
  --     probe13 : in std_logic_vector(7 downto 0) := (others=> '0');
  --     probe14 : in std_logic_vector(2 downto 0) := (others=> '0')
  --     );
  -- end component;
  -- component ila_sysMon is
  --   port (
  --     clk : in std_logic := '0';
  --     probe0 : in std_logic_vector(15 downto 0) := (others=> '0');
  --     probe1 : in std_logic_vector(15 downto 0) := (others=> '0');
  --     probe2 : in std_logic_vector(15 downto 0) := (others=> '0');
  --     probe3 : in std_logic_vector(15 downto 0) := (others=> '0');
  --     probe4 : in std_logic_vector(7 downto 0) := (others=> '0');
  --     probe5 : in std_logic_vector(7 downto 0) := (others=> '0');
  --     probe6 : in std_logic_vector(1 downto 0) := (others=> '0')
  --     );
  -- end component;

  -- SYSMON module signals
  signal sysmon_daddr : std_logic_vector(7 downto 0) := (others => '0');
  signal sysmon_dout  : std_logic_vector(15 downto 0);
  signal sysmon_drdy  : std_logic;
  signal sysmon_den   : std_logic := '0';
  signal sysmon_alm   : std_logic_vector(15 downto 0);
  signal q_strobe  : std_logic;
  signal q2_strobe : std_logic;

  -- Voltage monitoring ADC signals
  type t_csstates is (S_CS_IDLE, S_CS_SET);
  signal csstate : t_csstates := S_CS_IDLE;

  -- for voltage monitoring (CS, DIN, CLK)
  signal adc_cs_inner : std_logic_vector(4 downto 0);
  signal adc_din_inner : std_logic;
  signal cs_inner: std_logic;
  signal din_inner : std_logic;
  signal clk_inner : std_logic;
  signal chip_selected : std_logic_vector(4 downto 0) := (others => '0');

  -- vme command decoding
  signal cmddev : std_logic_vector (15 downto 0);
  signal r_sys_mon: std_logic := '0';
  signal w_vol_mon: std_logic := '0';
  signal r_vol_mon: std_logic := '0';
  signal which_chip : std_logic_vector(3 downto 0); -- there are 5 MAX1271 chips in total
  signal which_chan : std_logic_vector(3 downto 0); -- there are 8 channels to read per chip
  signal which_chip_inner : std_logic_vector(3 downto 0); -- there are 5 MAX1271 chips in total
  signal which_chan_inner : std_logic_vector(3 downto 0); -- there are 8 channels to read per chip

  -- internal buses to save voltage readings
  type t_vmondata_arr is array (integer range<>) of std_logic_vector(11 downto 0);
  signal vmon_dout_chan : t_vmondata_arr(7 downto 0);

  -- signals in/out odmb7_voltageMon
  signal vmon_dout : std_logic_vector(11 downto 0) := x"000";
  signal vmon_dout_valid: std_logic := '0';
  signal vmon_chanidx : integer range -1 to 6 := 0;
  signal vmon_chipidx : integer range -1 to 6 := 0;
  signal vmon_n_valid: integer := 0;
  signal startchannelvalid: std_logic := '0';
  signal startchannelvalid2: std_logic := '0';
  signal data_done: std_logic := '0';
  signal ctrlseqdone: std_logic := '0';
  signal data_valid_cntr : std_logic_vector(7 downto 0) := x"00";
  signal current_channel : std_logic_vector(2 downto 0) := "000";

  signal dd_dtack, d_dtack, q_dtack : std_logic;
  signal outdata_inner : std_logic_vector(15 downto 0);

  -- for ila
  signal variousflags: std_logic_vector(15 downto 0) := x"0000";
  signal ila_trigger: std_logic_vector(7 downto 0) := x"00";
  signal ila_adc : std_logic_vector(7 downto 0);

  signal sysmon_trigger  : std_logic_vector(7 downto 0) := (others=> '0');
  signal sysmon_data : std_logic_vector(1 downto 0) := (others=> '0');

begin

  -- decode command
  cmddev <= "000" & DEVICE & COMMAND & "00";

  -- command R 7XY0, to use the SYSMON module, XY is the channel number of SYSMON module
  r_sys_mon <= '1' when (device = '1' and WRITER = '1' and r_vol_mon = '0') else '0';
  -- command W 73Y0, where Y represent nth MAX1271 chip to read, vmedata can be anything
  w_vol_mon <= '1' when (cmddev(15 downto 8) = x"13" and WRITER = '0') else '0';
  -- command R 74Y0, where Y represent nth MAX1271 chip to read
  r_vol_mon <= '1' when (cmddev(15 downto 8) = x"14" and WRITER = '1') else '0';

  -- this signal is not actually used in reading vmon_dout_inner
  which_chip <= cmddev(7 downto 4) when (w_vol_mon = '1') else x"0";
  which_chan <= cmddev(7 downto 4) when (r_vol_mon = '1') else x"0";

  -- this is the SYSMON channel
  sysmon_daddr <= cmddev(11 downto 4) when (r_sys_mon = '1') else x"00";

  -- when w_vol_mon has a rising edge, trigger a sequence sent to MAX1271
  u1_oneshot : oneshot port map (trigger => w_vol_mon, clk => SLOWCLK, pulse => startchannelvalid);
  u2_oneshot : oneshot port map (trigger => startchannelvalid, clk => SLOWCLK, pulse => startchannelvalid2);

  -------------------------------------------------------------------------------------------
  -- Voltage monitoring FSM and instantiation
  -------------------------------------------------------------------------------------------

  -- need to keep which_chip persistent as we are reading 8 channels from 1 chip in one go
  -- which_channel_inner is probably not neccessary in the end
  which_inner_gen : for I in 3 downto 0 generate
  begin
    which_chip_inner_gen_i: FDCE port map(Q => which_chip_inner(I), C => SLOWCLK, CLR => data_done, CE => DEVICE, D => which_chip(I));
    which_chan_inner_gen_i: FDCE port map(Q => which_chan_inner(I), C => SLOWCLK, CLR => data_done, CE => DEVICE, D => which_chan(I));
  end generate which_inner_gen;
  
  vmon_chanidx <= to_integer(unsigned(which_chan_inner)) - 1;
  vmon_chipidx <= to_integer(unsigned(which_chip_inner)) - 1;
  -- sync DIN and CS using same clk
  
  --chip_selected(1) <= '0';
  
  cs_gen : for I in 3 downto 1 generate
  begin
    --chip_selected(I) <= '0';
    chip_selected(I) <= '1' when (vmon_chipidx = I) else '0';
    --need FDPE_1 for falling edge
    cs_gen_i: FDPE_1 port map(Q => adc_cs_inner(I), C => SLOWCLK, PRE => data_done, CE => chip_selected(I), D => cs_inner);
  end generate cs_gen;
  din_gen_i: FDCE port map(Q => adc_din_inner, C => SLOWCLK, CLR => data_done, CE => or_reduce(which_chip_inner), D => din_inner);

  process (SLOWCLK)
  begin
    if rising_edge(SLOWCLK) then
      if (DEVICE = '1' or data_done = '1') then
        vmon_n_valid <= 0;
      elsif (vmon_dout_valid = '1') then
        vmon_dout_chan(vmon_n_valid) <= vmon_dout;
        vmon_n_valid <= vmon_n_valid + 1;
      end if;
    end if; -- CLK1P25
  end process;

  u_voltageMon : voltage_mon
    port map (
      CLK  => SLOWCLK, -- 1.25 MHz
      CS   => cs_inner,
      DIN  => din_inner,
      SCK  => clk_inner,
      DOUT => ADC_DOUT,
      DVOUT => vmon_dout_valid,
      DATA => vmon_dout,
      DATADONE => data_done,
      DATAVALIDCNTR => data_valid_cntr,
      CURRENTCHANNELOUT => current_channel,
      CTRLSEQDONE => ctrlseqdone,
      startchannelvalid => startchannelvalid2
      );

  ADC_SCK  <= clk_inner;
  ADC_DIN  <= adc_din_inner;
  ADC_CS_B <= adc_cs_inner;

  -------------------------------------------------------------------------------------------
  -- SYSMON module instantiation
  -------------------------------------------------------------------------------------------
  -- TODO: Find out the SYSMON configurations and assign the DADDR
  sysmone1_inst : SYSMONE1
    generic map (
      INIT_40 => x"3000",    -- Set to average 256 samples
      INIT_41 => x"2080",    -- Set continuous sequence mode, and calibration mode CAL3
      INIT_42 => x"0A00",    -- Set DCLK division for the ADC clock to 10
      INIT_48 => x"7F01",    -- Turns on the voltage monitors
      INIT_49 => x"FFFF",    -- Turns on all the ADC channels
      INIT_4A => x"0F00",    -- Enable averaging for temperature and Vcc
      INIT_4B => x"FFFF",    -- Enable averaging for all ADC channels
      INIT_4C => x"0000",    -- Sequencer Bipolar selection
      INIT_4D => x"0000",    -- Sequencer Bipolar selection
      INIT_4E => x"0800",    -- Set Acquisition time as 10 ADCCLK cycles
      INIT_4F => x"FFFF",    -- Set Acquisition time as 10 ADCCLK cycles
      INIT_50 => x"B5ED",    -- Temp upper alarm limit
      INIT_51 => x"5999",    -- Vccint upper alarm limit
      INIT_52 => x"E000",    -- Vccaux upper alarm limit
      INIT_53 => x"B5C3",    -- Temp alarm OT upper (Default 125C -> ca33, 85C -> b5c3)
      INIT_54 => x"A93A",    -- Temp lower alarm limit
      INIT_55 => x"5111",    -- Vccint lower alarm limit
      INIT_56 => x"CAAA",    -- Vccaux lower alarm limit
      INIT_57 => x"B0CE",    -- Temp alarm OT reset (Default 70C -> ae4e, 75C -> b0ce)
      SIM_MONITOR_FILE => "sysmon_design.txt" --avoid simulation errors
      )
    port map (
      ALM => sysmon_alm,     -- to be connected
      OT => open,
      DO => sysmon_dout,
      DRDY => sysmon_drdy,
      BUSY => open,
      CHANNEL => open,
      EOC => open,
      EOS => open,
      JTAGBUSY => open,
      JTAGLOCKED => open,
      JTAGMODIFIED => open,
      MUXADDR => open,
      VAUXN => VAUXN, -- 16 bits AD[0-15]N
      VAUXP => VAUXP, -- 16 bits AD[0-15]P
      CONVST => '0',
      CONVSTCLK => '0',
      RESET => RST,
      VN => '0',
      VP => '0',
      DADDR => sysmon_daddr,
      DCLK => FASTCLK,
      DEN => sysmon_den,
      DI => x"0000",
      DWE => '0',
      I2C_SCLK => '0',
      I2C_SDA => '0'
      );

  OUTDATA <= outdata_inner;
  outdata_inner <= x"0" & vmon_dout_chan(vmon_chanidx) when (r_vol_mon = '1') else
                   x"0" & sysmon_dout(15 downto 4)     when (r_sys_mon = '1') else -- Discarding the 4 LSB
                   (others => 'L');

  -- Enable sysmon output in first full clock cycle after strobe goes high
  FD_STROBE  : FD port map (Q => q_strobe, C => FASTCLK, D => STROBE);
  FD_STROBE2 : FD port map (Q => q2_strobe, C => FASTCLK, D => q_strobe);
  sysmon_den <= '1' when (r_sys_mon = '1' and q2_strobe = '0' and q_strobe = '1') else '0';

  -- DTACK when OUTDATA contains valid data
  dd_dtack <= device and strobe; -- and drdy;
  FD_D_DTACK : FDC port map(Q => d_dtack, C => dd_dtack, CLR=> q_dtack, D => '1');
  FD_Q_DTACK : FD port map(Q => q_dtack, C => SLOWCLK, D => d_dtack);
  DTACK <= q_dtack;

  ila_trigger <= "000" & data_done & DEVICE & STROBE & vmon_dout_valid & startchannelvalid;
  variousflags <= "00" & ctrlseqdone & which_chan & which_chan_inner & STROBE & DEVICE & vmon_dout_valid & data_done & cs_inner;
  ila_adc <= clk_inner & "0" & adc_cs_inner & adc_din_inner;

  -- -- ILA for voltageMon debug
  -- i_ila : ila_volMon
  --   port map(
  --     clk => FASTCLK,
  --     probe0 => ila_trigger,
  --     probe1 => variousflags,
  --     probe2 => vmon_dout,
  --     probe3 => x"000",
  --     probe4 => ila_adc,
  --     probe5 => vmon_dout_chan(0),
  --     probe6 => vmon_dout_chan(1),
  --     probe7 => vmon_dout_chan(2),
  --     probe8 => vmon_dout_chan(3),
  --     probe9 => vmon_dout_chan(4),
  --     probe10 => vmon_dout_chan(5),
  --     probe11 => vmon_dout_chan(6),
  --     probe12 => vmon_dout_chan(7),
  --     probe13 => data_valid_cntr,
  --     probe14 => current_channel
  --     );

  -- -- ILA for sysMon debug
  -- j_ila : ila_sysMon
  --   port map(
  --     clk => FASTCLK,
  --     probe0 => cmddev,
  --     probe1 => sysmon_alm,
  --     probe2 => sysmon_dout,
  --     probe3 => outdata_inner,
  --     probe4 => sysmon_daddr,
  --     probe5 => sysmon_trigger,
  --     probe6 => sysmon_data
  --     );

  sysmon_trigger(0) <= SLOWCLK;
  sysmon_trigger(1) <= DEVICE;
  sysmon_trigger(2) <= STROBE;
  sysmon_trigger(3) <= WRITER;
  sysmon_trigger(4) <= r_sys_mon;
  sysmon_trigger(5) <= r_vol_mon;
  sysmon_trigger(6) <= w_vol_mon;
  sysmon_trigger(7) <= RST;

  sysmon_data(0) <= sysmon_drdy;
  sysmon_data(1) <= sysmon_den;

end SYSTEM_MON_ARCH;
