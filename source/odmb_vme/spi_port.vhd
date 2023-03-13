library ieee;
library work;
library UNISIM;
use UNISIM.vcomponents.all;
use work.Latches_Flipflops.all;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ucsb_types.all;

--! @brief VME device that acts as user interface to EPROM
--! @details Replaces BPI_PORT and BPI_CFG_CONTROLLER modules from legacy ODMB firmware.
--! Supported VME commands:
--! * W 6000 write configuration registers to PROM
--! * W 6004 load configuration registers from PROM
--! * W 6010 write constant registers to PROM
--! * W 6014 load constant registers from PROM
--! * W 6020 reset SPI_CTRL finite state machine
--! * W 6024 disable SPI_CTRL finite state machine
--! * W 6028 enable SPI_CTRL finite state machine
--! * W 602C XXXX write XXXX to SPI command FIFO. See SPI_CTRL for details.
--! * R 6030 read 1 word from readback FIFO
--! * R 6034 read number of words in readback FIFO
--! * R 6038 read SPI status
--! * R 603C read BPI timer (16 LSB)
--! * R 6040 read BPI timer (16 MSB)
--! Other features:
--! * upload CONST and CFG registers on reset
entity SPI_PORT is
  port (
    SLOWCLK              : in std_logic; --! 2.5 MHz clock input
    CLK                  : in std_logic; --! 40 MHz clock input
    RST                  : in std_logic; --! Soft reset signal
    --VME signals
    DEVICE               : in  std_logic;                     --! Indicates whether this is the selected VME device
    STROBE               : in  std_logic;                     --! Indicates VME command is ready to be executed
    COMMAND              : in  std_logic_vector(9 downto 0);  --! VME command to be executed (x"6" & COMMAND & "00" is user-readable version)
    WRITER               : in  std_logic;                     --! Indicates if VME command is a read or write command
    DTACK                : out std_logic;                     --! Data acknowledge to be sent once command is initialized/executed
    INDATA               : in  std_logic_vector(15 downto 0); --! Input data from VME backplane
    OUTDATA              : out std_logic_vector(15 downto 0); --! Output data to VME backplane
    --CONFREGS signals
    SPI_CFG_UL_PULSE     : out std_logic;                     --! Signal to VMECONFREGS to write CFG registers read from PROM
    SPI_CONST_UL_PULSE   : out std_logic;                     --! Signal to VMECONFREGS to write const registers read from PROM
    SPI_UL_REG           : out std_logic_vector(15 downto 0); --! Contents of CFG/const registers read from PROM
    SPI_CFG_BUSY         : out std_logic;                     --! Indicates CFG register upload in progress
    SPI_CONST_BUSY       : out std_logic;                     --! Indicated const register upload in progress
    SPI_CFG_REG_WE       : out integer range 0 to NREGS;      --! Write enable for each CFG register
    SPI_CONST_REG_WE     : out integer range 0 to NREGS;      --! Write enable for each const register
    SPI_CFG_REGS         : in cfg_regs_array;                 --! Contents of CFG registers to write to PROM
    SPI_CONST_REGS       : in cfg_regs_array;                 --! Contents of const registers to write PROM
    --signals to/from SPI_CTRL
    SPI_RST                   : out std_logic;                     --! reset signal for SPI_CTRL state machine
    SPI_ENBL                  : out std_logic;                     --! signal to enable SPI_CTRL state machine
    SPI_DSBL                  : out std_logic;                     --! signal to disable SPI_CTRL state machine
    SPI_CMD_FIFO_WRITE_EN     : out std_logic;                     --! Write enable to write command to PROM controller module
    SPI_CMD_FIFO_IN           : out std_logic_vector(15 downto 0); --! Command to be written to PROM controller module
    SPI_READBACK_FIFO_OUT     : in std_logic_vector(15 downto 0);  --! Contents readback from PROM
    SPI_READBACK_FIFO_READ_EN : out std_logic;                     --! Read enable to progress through contents readback from PROM
    SPI_READ_BUSY             : in std_logic;                      --! Indicates a PROM read in progress
    SPI_RBK_WRD_CNT           : in std_logic_vector(10 downto 0);  --! Number of words in SPI readback FIFO
    SPI_TIMER                 : in std_logic_vector(31 downto 0);  --! SPI timer register from SPI_CTRL
    SPI_STATUS                : in std_logic_vector(15 downto 0);  --! SPI status register from SPI_CTRL
    --debug
    DIAGOUT                   : out std_logic_vector(17 downto 0)  --! Debug signals
    );
end SPI_PORT;

architecture SPI_PORT_Arch of SPI_PORT is

  --signal cfg_reg_hardcode : cfg_regs_array := (x"0019", x"FFF1", x"0001", x"FFF3",
  --                                               x"0008", x"0008", x"0004", x"0000",
  --                                               x"D3B7", x"D3B7", x"00FF", x"0100",
  --                                               x"FFFC", x"FFFD", x"FFFE", x"FFFF");
  
  -- component ila_spi
  -- port (
  --   clk : in std_logic;
  --   probe0 : in std_logic_vector(511 downto 0)
  --   );
  -- end component;
  
  --CFG register download signals
  type cfg_download_states is (S_IDLE, S_SET_ADDR_LOWER, S_ERASE, S_BUFFER_PROGRAM, S_WRITE);
  signal cfg_download_state             : cfg_download_states := S_IDLE;
  signal spi_cmd_fifo_write_en_cfg_dl   : std_logic := '0';
  signal spi_cmd_fifo_in_cfg_dl         : std_logic_vector(15 downto 0) := x"0000";
  signal download_cfg_reg_index         : integer := 0;

  --const register download signals
  signal const_download_state           : cfg_download_states := S_IDLE;
  signal spi_cmd_fifo_write_en_const_dl : std_logic := '0';
  signal spi_cmd_fifo_in_const_dl       : std_logic_vector(15 downto 0) := x"0000";
  signal download_const_reg_index       : integer := 0;
  
  --CFG register upload signals
  type cfg_upload_states is (S_IDLE, S_SET_ADDR_LOWER, S_READN, S_WAIT_READ_BUSY, S_WAIT_READ_DONE, S_WAIT_READ_STALL, S_READBACK);
  signal cfg_upload_state                   : cfg_upload_states := S_IDLE;
  signal spi_cmd_fifo_write_en_cfg_ul       : std_logic := '0';
  signal spi_cmd_fifo_in_cfg_ul             : std_logic_vector(15 downto 0) := x"0000";
  signal upload_cfg_reg_index               : integer := 0;  
  signal spi_readback_fifo_read_en_cfg_ul   : std_logic := '0';
  signal spi_cfg_ul_pulse_inner             : std_logic := '0';
  signal spi_cfg_reg_we_inner               : integer := NREGS;
  signal spi_cfg_ul_reg                     : std_logic_vector(15 downto 0) := x"0000";
  signal cfg_readback_fifo_stall_counter    : unsigned(7 downto 0) := x"FF"; --was 1F but read counter got offset

  --const register upload signals
  signal const_upload_state                 : cfg_upload_states := S_IDLE;
  signal spi_cmd_fifo_write_en_const_ul     : std_logic := '0';
  signal spi_cmd_fifo_in_const_ul           : std_logic_vector(15 downto 0) := x"0000";
  signal upload_const_reg_index             : integer := 0;  
  signal spi_readback_fifo_read_en_const_ul : std_logic := '0';
  signal spi_const_ul_pulse_inner           : std_logic := '0';
  signal spi_const_reg_we_inner             : integer := NREGS;
  signal spi_const_ul_reg                   : std_logic_vector(15 downto 0) := x"0000";
  signal const_readback_fifo_stall_counter  : unsigned(7 downto 0) := x"FF";

  signal ul_dl_busy                         : std_logic := '0';
  
  --SPI command command signals
  signal strobe_meta               : std_logic := '0';
  signal strobe_q                  : std_logic := '0';
  signal strobe_qq                 : std_logic := '0';
  signal strobe_pulse              : std_logic := '0';
  signal spi_cmd_fifo_write_en_cmd : std_logic := '0';
  signal spi_cmd_fifo_in_cmd       : std_logic_vector(15 downto 0) := x"0000";
  
  --SPI read signals
  signal spi_read_data                 : std_logic_vector(15 downto 0) := x"0000";
  signal spi_readback_fifo_read_en_cmd : std_logic := '0';
  
  --command parsing signals
  signal cmddev                       : std_logic_vector(15 downto 0) := x"0000";
  signal do_cfg_read                  : std_logic := '0';
  signal do_cfg_write                 : std_logic := '0'; 
  signal do_const_read                : std_logic := '0';
  signal do_const_write               : std_logic := '0'; 
  signal do_spi_cmd                   : std_logic := '0';
  signal do_spi_read                  : std_logic := '0';
  signal do_read_readback_fifo_nwords : std_logic := '0';
  signal do_reset_spi_fsm             : std_logic := '0';
  signal do_enable_spi_fsm            : std_logic := '0';
  signal do_disable_spi_fsm           : std_logic := '0';
  signal do_read_timer_lsb            : std_logic := '0';
  signal do_read_timer_msb            : std_logic := '0';
  signal do_read_status               : std_logic := '0';

  --signals for uploading registers on reset
  type rst_upload_states is (S_IDLE, S_WAIT, S_CFG_PULSE, S_CFG_WAIT, S_CONST_PULSE, S_CONST_WAIT);
  signal rst_upload_state   : rst_upload_states := S_IDLE;
  signal rst_q              : std_logic := '0';
  signal rst_pulse          : std_logic := '0';
  signal rst_sync           : std_logic := '0';
  signal rst_wait_counter   : unsigned(7 downto 0) := x"00";
  signal startup_cfg_read   : std_logic := '0';
  signal startup_const_read : std_logic := '0';
  
  --dtack signals
  signal ce_d_dtack : std_logic := '0'; 
  signal d_dtack    : std_logic := '0';
  signal q_dtack    : std_logic := '0';
  
  --debugging signals
  signal outdata_inner         : std_logic_vector(15 downto 0) := x"0000";
  signal ila_probe             : std_logic_vector(511 downto 0) := (others => '0');

begin

  -- --debug
  -- ila_spi_port_i : ila_spi
  -- PORT MAP (
  --   clk => CLK,
  --   probe0 => ila_probe
  -- );
  ila_probe(0) <= DEVICE;
  ila_probe(1) <= STROBE;
  ila_probe(3 downto 2) <= "00";
  ila_probe(13 downto 4) <= command;
  ila_probe(17 downto 14) <= "0110";
  ila_probe(18) <= q_dtack;
  ila_probe(34 downto 19) <= INDATA;
  ila_probe(50 downto 35) <= outdata_inner;
  ila_probe(51) <= strobe_pulse;
  ila_probe(52) <= do_cfg_write;
  ila_probe(53) <= do_cfg_read;
  ila_probe(54) <= spi_cmd_fifo_write_en_cmd;
  ila_probe(55) <= spi_cmd_fifo_write_en_cfg_dl;
  ila_probe(56) <= spi_cmd_fifo_write_en_cfg_ul;
  ila_probe(72 downto 57) <= spi_cmd_fifo_in_cmd;
  ila_probe(88 downto 73) <= spi_cmd_fifo_in_cfg_ul;
  ila_probe(104 downto 89) <= spi_cmd_fifo_in_cfg_dl;
  ila_probe(105) <= spi_readback_fifo_read_en_cmd;
  ila_probe(106) <= spi_readback_fifo_read_en_cfg_ul;
  ila_probe(107) <= spi_cfg_ul_pulse_inner;
  ila_probe(111 downto 108) <= std_logic_vector(to_unsigned(upload_cfg_reg_index,4));
  ila_probe(127 downto 112) <= spi_cfg_ul_reg;
  
  --Decode command
  cmddev    <= "000" & DEVICE & COMMAND & "00";

  do_cfg_write                 <= '1' when (cmddev=x"1000" and STROBE='1') else '0'; --0x6000
  do_cfg_read                  <= '1' when (cmddev=x"1004" and STROBE='1') else '0'; --0x6004
  do_const_write               <= '1' when (cmddev=x"1010" and STROBE='1') else '0'; --0x6010
  do_const_read                <= '1' when (cmddev=x"1014" and STROBE='1') else '0'; --0x6014
  do_reset_spi_fsm             <= '1' when (cmddev=x"1020" and STROBE='1') else '0'; --0x6020
  do_disable_spi_fsm           <= '1' when (cmddev=x"1024" and STROBE='1') else '0'; --0x6024
  do_enable_spi_fsm            <= '1' when (cmddev=x"1028" and STROBE='1') else '0'; --0x6028
  do_spi_cmd                   <= '1' when (cmddev=x"102C") else '0';                --0x602C
  do_spi_read                  <= '1' when (cmddev=x"1030") else '0';                --0x6030
  do_read_readback_fifo_nwords <= '1' when (cmddev=x"1034") else '0';                --0x6034
  do_read_status               <= '1' when (cmddev=x"1038") else '0';                --0x6034
  do_read_timer_lsb            <= '1' when (cmddev=x"103C") else '0';                --0x603C
  do_read_timer_msb            <= '1' when (cmddev=x"1040") else '0';                --0x6040

  --generate strobe_pulse in SLOWCLK domain, note STROBE comes from FASTCLK clock domain
  strobe_meta  <= STROBE when rising_edge(SLOWCLK);
  strobe_q     <= strobe_meta when rising_edge(SLOWCLK);
  strobe_qq    <= strobe_q when rising_edge(SLOWCLK);
  strobe_pulse <= (not strobe_qq) and strobe_q;
  
  --handle SPI command command (602C)
  spi_cmd_fifo_write_en_cmd <= do_spi_cmd and strobe_pulse and not ul_dl_busy;
  spi_cmd_fifo_in_cmd <= INDATA;
  
  --generate SPI FSM signals (6020, 6024, 6028) (TODO: check that no operation (ex. cfg register write) in progress?)
  SPI_RST  <= do_reset_spi_fsm and strobe_pulse;
  SPI_DSBL <= do_disable_spi_fsm and strobe_pulse;
  SPI_ENBL <= do_enable_spi_fsm and strobe_pulse;        
  
  --handle RBK FIFO read/word count/timer bits commands
  outdata_inner <= "00000" & SPI_RBK_WRD_CNT when (do_read_readback_fifo_nwords = '1') else
                   SPI_STATUS when (do_read_status = '1') else
                   SPI_TIMER(15 downto 0) when (do_read_timer_lsb = '1') else
                   SPI_TIMER(31 downto 16) when (do_read_timer_msb = '1') else
                   spi_read_data;
  OUTDATA <= outdata_inner; --temp, for debugging
  
  ul_dl_busy <= '1' when (cfg_download_state /= S_IDLE) else 
                '1' when (cfg_upload_state /= S_IDLE) else
                '1' when (const_download_state /= S_IDLE) else
                '1' when (const_upload_state /= S_IDLE) else
                '0';
                
  rst_q <= RST when rising_edge(CLK);
  rst_pulse <= RST and (not rst_q);
  slowclk_domain_reset : PULSE2SLOW port map(DOUT => rst_sync, CLK_DOUT => SLOWCLK, CLK_DIN => CLK, RST => '0', DIN => rst_pulse);

  --load registers on reset
  reset_proc : process (SLOWCLK)
  begin
  if rising_edge(SLOWCLK) then
    case rst_upload_state is
      when S_IDLE => 
        rst_wait_counter <= x"00";
        startup_cfg_read <= '0';
        startup_const_read <= '0';
        if (rst_sync = '1') then
          rst_upload_state <= S_WAIT;
        else
          rst_upload_state <= S_IDLE;
        end if;

      when S_WAIT =>
        rst_wait_counter <= rst_wait_counter + 1;
        startup_cfg_read <= '0';
        startup_const_read <= '0';
        if (rst_wait_counter = x"FF") then --previously 20 fastclk cycles = 1.25 slowclk cycles
          rst_upload_state <= S_CFG_PULSE;
        else
          rst_upload_state <= S_WAIT;
        end if;

      when S_CFG_PULSE =>
        rst_wait_counter <= rst_wait_counter + 1;
        startup_cfg_read <= '1';
        startup_const_read <= '0';
        if (rst_wait_counter = x"01") then --starts on 0
          rst_upload_state <= S_CFG_WAIT;
        else
          rst_upload_state <= S_CFG_PULSE;
        end if;
        
      when S_CFG_WAIT =>
        rst_wait_counter <= x"00";
        startup_cfg_read <= '0';
        startup_const_read <= '0';
        if (cfg_upload_state = S_IDLE) then
          rst_upload_state <= S_CONST_PULSE;
        else
          rst_upload_state <= S_CFG_WAIT;
        end if;
      
      when S_CONST_PULSE =>
        rst_wait_counter <= rst_wait_counter + 1;
        startup_cfg_read <= '0';
        startup_const_read <= '1';
        if (rst_wait_counter = x"01") then --starts on 0
          rst_upload_state <= S_CONST_WAIT;
        else
          rst_upload_state <= S_CONST_PULSE;
        end if;

      when S_CONST_WAIT =>
        rst_wait_counter <= x"00";
        startup_cfg_read <= '0';
        startup_const_read <= '0';
        if (const_upload_state = S_IDLE) then
          rst_upload_state <= S_IDLE;
        else
          rst_upload_state <= S_CONST_WAIT;
        end if;

      when others =>
        rst_upload_state <= S_IDLE;
    end case;
  end if;
  end process;
             
  --pop 1 word from FIFO on read command
  spi_read_proc : process (SLOWCLK)
  begin
  if rising_edge(SLOWCLK) then
    if (do_spi_read='1' and strobe_pulse='1') then
      spi_read_data <= SPI_READBACK_FIFO_OUT;
      spi_readback_fifo_read_en_cmd <= '1';
    else
      spi_read_data <= spi_read_data;
      spi_readback_fifo_read_en_cmd <= '0';
    end if;
  end if;
  end process;

  --handle CFG write command
  cfg_write_proc : process (SLOWCLK)
  begin
  if rising_edge(SLOWCLK) then
    case cfg_download_state is
    when S_IDLE => 
      if do_cfg_write='1' and ul_dl_busy='0' then
        spi_cmd_fifo_write_en_cfg_dl <= '1';
        --send CMD to load address 00FE0000
        spi_cmd_fifo_in_cfg_dl <= x"1FD7";
        cfg_download_state <= S_SET_ADDR_LOWER;
      else
        spi_cmd_fifo_write_en_cfg_dl <= '0';
        spi_cmd_fifo_in_cfg_dl <= x"0000";
        cfg_download_state <= S_IDLE;
      end if;
      
    when S_SET_ADDR_LOWER =>
      spi_cmd_fifo_write_en_cfg_dl <= '1';
      --load address lower bits
      spi_cmd_fifo_in_cfg_dl <= x"0000";
      cfg_download_state <= S_ERASE;
    
    when S_ERASE =>
      spi_cmd_fifo_write_en_cfg_dl <= '1';
      --send CMD to erase block
      spi_cmd_fifo_in_cfg_dl <= x"000A";
      cfg_download_state <= S_BUFFER_PROGRAM;

    when S_BUFFER_PROGRAM =>
      spi_cmd_fifo_write_en_cfg_dl <= '1';
      --send CMD to buffer 16 word program
      spi_cmd_fifo_in_cfg_dl <= x"01EC";
      cfg_download_state <= S_WRITE;

    when S_WRITE =>
      spi_cmd_fifo_write_en_cfg_dl <= '1';
      --send CFG registers as program data
      spi_cmd_fifo_in_cfg_dl <= SPI_CFG_REGS(download_cfg_reg_index);
      if (download_cfg_reg_index=15) then
        download_cfg_reg_index <= 0;
        cfg_download_State <= S_IDLE;
      else
        download_cfg_reg_index <= download_cfg_reg_index + 1;
        cfg_download_state <= S_WRITE;
      end if;

    end case;
  end if;
  end process;


  --handle const write command
  const_write_proc : process (SLOWCLK)
  begin
  if rising_edge(SLOWCLK) then
    case const_download_state is
    when S_IDLE => 
      if do_const_write='1' and ul_dl_busy='0' then
        spi_cmd_fifo_write_en_const_dl <= '1';
        --send CMD to load address 00FE0000
        spi_cmd_fifo_in_const_dl <= x"1FB7";
        const_download_state <= S_SET_ADDR_LOWER;
      else
        spi_cmd_fifo_write_en_const_dl <= '0';
        spi_cmd_fifo_in_const_dl <= x"0000";
        const_download_state <= S_IDLE;
      end if;
      
    when S_SET_ADDR_LOWER =>
      spi_cmd_fifo_write_en_const_dl <= '1';
      --load address lower bits
      spi_cmd_fifo_in_const_dl <= x"0000";
      const_download_state <= S_ERASE;
    
    when S_ERASE =>
      spi_cmd_fifo_write_en_const_dl <= '1';
      --send CMD to erase block
      spi_cmd_fifo_in_const_dl <= x"000A";
      const_download_state <= S_BUFFER_PROGRAM;

    when S_BUFFER_PROGRAM =>
      spi_cmd_fifo_write_en_const_dl <= '1';
      --send CMD to buffer 16 word program
      spi_cmd_fifo_in_const_dl <= x"01EC";
      const_download_state <= S_WRITE;

    when S_WRITE =>
      spi_cmd_fifo_write_en_const_dl <= '1';
      --send CFG registers as program data
      spi_cmd_fifo_in_const_dl <= SPI_CONST_REGS(download_const_reg_index);
      if (download_const_reg_index=15) then
        download_const_reg_index <= 0;
        const_download_State <= S_IDLE;
      else
        download_const_reg_index <= download_const_reg_index + 1;
        const_download_state <= S_WRITE;
      end if;

    end case;
  end if;
  end process;
  
  
  --handle CFG read command
  cfg_upload_proc : process (SLOWCLK)
  begin
  if rising_edge(SLOWCLK) then
    case cfg_upload_state is
    when S_IDLE => 
      spi_readback_fifo_read_en_cfg_ul <= '0';
      spi_cfg_ul_pulse_inner <= '0';
      spi_cfg_reg_we_inner <= NREGS;
      spi_cfg_ul_reg <= x"0000";
      if (do_cfg_read='1' or startup_cfg_read='1') and ul_dl_busy='0' then
        spi_cmd_fifo_write_en_cfg_ul <= '1';
        --send CMD to load address 00FE0000
        spi_cmd_fifo_in_cfg_ul <= x"1FD7";
        cfg_upload_state <= S_SET_ADDR_LOWER;
      else
        spi_cmd_fifo_write_en_cfg_ul <= '0';
        spi_cmd_fifo_in_cfg_ul <= x"0000";
        cfg_upload_state <= S_IDLE;
      end if;
     
    when S_SET_ADDR_LOWER =>
      spi_cmd_fifo_write_en_cfg_ul <= '1';
      spi_readback_fifo_read_en_cfg_ul <= '0';
      spi_cfg_ul_pulse_inner <= '0';
      spi_cfg_reg_we_inner <= NREGS;
      spi_cfg_ul_reg <= x"0000";
      --load address lower bits
      spi_cmd_fifo_in_cfg_ul <= x"0000";
      cfg_upload_state <= S_READN;
     
    when S_READN =>
      spi_cmd_fifo_write_en_cfg_ul <= '1';
      spi_readback_fifo_read_en_cfg_ul <= '0';
      --send CMD to read 16 words
      spi_cmd_fifo_in_cfg_ul <= x"01E4";
      cfg_upload_state <= S_WAIT_READ_BUSY;
      
    when S_WAIT_READ_BUSY =>
      spi_cmd_fifo_write_en_cfg_ul <= '0';
      spi_readback_fifo_read_en_cfg_ul <= '0';
      spi_cfg_ul_pulse_inner <= '0';
      spi_cfg_reg_we_inner <= NREGS;
      spi_cfg_ul_reg <= x"0000";
      --wait for spi_ctrl to start reading
      spi_cmd_fifo_in_cfg_ul <= x"0000";
      if (SPI_READ_BUSY='1') then
        cfg_upload_state <= S_WAIT_READ_DONE;      
      else
        cfg_upload_state <= S_WAIT_READ_BUSY;
      end if;
      
    when S_WAIT_READ_DONE =>
        spi_cmd_fifo_write_en_cfg_ul <= '0';
        spi_cfg_ul_pulse_inner <= '0';
        spi_cfg_reg_we_inner <= NREGS;
        spi_cfg_ul_reg <= x"0000";
        --wait for spi_ctrl to finish reading
        spi_cmd_fifo_in_cfg_ul <= x"0000";
        upload_cfg_reg_index <= 0;
        spi_readback_fifo_read_en_cfg_ul <= '0';
        if (SPI_READ_BUSY='1') then
          cfg_upload_state <= S_WAIT_READ_STALL;    
        else
          cfg_upload_state <= S_WAIT_READ_DONE;
        end if;
        
    when S_WAIT_READ_STALL => 
      --wait for empty signal on fifo to go low
      spi_cmd_fifo_write_en_cfg_ul <= '0';
      spi_cfg_ul_pulse_inner <= '0';
      spi_cfg_reg_we_inner <= NREGS;
      spi_cfg_ul_reg <= SPI_READBACK_FIFO_OUT;
      spi_cmd_fifo_in_cfg_ul <= x"0000";
      upload_cfg_reg_index <= 0;
      if (cfg_readback_fifo_stall_counter=x"0") then
        cfg_upload_state <= S_READBACK;           
        cfg_readback_fifo_stall_counter <= x"1F";
        spi_readback_fifo_read_en_cfg_ul <= '1';
      else
        cfg_upload_state <= S_WAIT_READ_STALL;
        cfg_readback_fifo_stall_counter <= cfg_readback_fifo_stall_counter - 1;
        spi_readback_fifo_read_en_cfg_ul <= '0';
      end if;
  
    when S_READBACK =>
      spi_cmd_fifo_write_en_cfg_ul <= '0';
      spi_cmd_fifo_in_cfg_ul <= x"0000";
      spi_cfg_ul_pulse_inner <= '1';
      spi_cfg_reg_we_inner <= upload_cfg_reg_index;
      spi_cfg_ul_reg <= SPI_READBACK_FIFO_OUT;
      --read values from readback fifo and send to CFG registers
      spi_cmd_fifo_in_cfg_ul <= x"0000";
      if (upload_cfg_reg_index=15) then
        upload_cfg_reg_index <= 0;
        spi_readback_fifo_read_en_cfg_ul <= '0';
        cfg_upload_State <= S_IDLE;
      else
        upload_cfg_reg_index <= upload_cfg_reg_index + 1;
        spi_readback_fifo_read_en_cfg_ul <= '1';
        cfg_upload_state <= S_READBACK;
      end if;
  
    end case;
  end if;
  end process;

  --handle CONST read command
  const_upload_proc : process (SLOWCLK)
  begin
  if rising_edge(SLOWCLK) then
    case const_upload_state is
    when S_IDLE => 
      spi_readback_fifo_read_en_const_ul <= '0';
      spi_const_ul_pulse_inner <= '0';
      spi_const_reg_we_inner <= NREGS;
      spi_const_ul_reg <= x"0000";
      if (do_const_read='1' or startup_const_read='1') and ul_dl_busy='0' then
        spi_cmd_fifo_write_en_const_ul <= '1';
        --send CMD to load address 00FE0000
        spi_cmd_fifo_in_const_ul <= x"1FB7";
        const_upload_state <= S_SET_ADDR_LOWER;
      else
        spi_cmd_fifo_write_en_const_ul <= '0';
        spi_cmd_fifo_in_const_ul <= x"0000";
        const_upload_state <= S_IDLE;
      end if;
     
    when S_SET_ADDR_LOWER =>
      spi_cmd_fifo_write_en_const_ul <= '1';
      spi_readback_fifo_read_en_const_ul <= '0';
      spi_const_ul_pulse_inner <= '0';
      spi_const_reg_we_inner <= NREGS;
      spi_const_ul_reg <= x"0000";
      --load address lower bits
      spi_cmd_fifo_in_const_ul <= x"0000";
      const_upload_state <= S_READN;
     
    when S_READN =>
      spi_cmd_fifo_write_en_const_ul <= '1';
      spi_readback_fifo_read_en_const_ul <= '0';
      --send CMD to read 16 words
      spi_cmd_fifo_in_const_ul <= x"01E4";
      const_upload_state <= S_WAIT_READ_BUSY;
      
    when S_WAIT_READ_BUSY =>
      spi_cmd_fifo_write_en_const_ul <= '0';
      spi_readback_fifo_read_en_const_ul <= '0';
      spi_const_ul_pulse_inner <= '0';
      spi_const_reg_we_inner <= NREGS;
      spi_const_ul_reg <= x"0000";
      --wait for spi_ctrl to start reading
      spi_cmd_fifo_in_const_ul <= x"0000";
      if (SPI_READ_BUSY='1') then
        const_upload_state <= S_WAIT_READ_DONE;      
      else
        const_upload_state <= S_WAIT_READ_BUSY;
      end if;
      
    when S_WAIT_READ_DONE =>
        spi_cmd_fifo_write_en_const_ul <= '0';
        spi_const_ul_pulse_inner <= '0';
        spi_const_reg_we_inner <= NREGS;
        spi_const_ul_reg <= x"0000";
        --wait for spi_ctrl to finish reading
        spi_cmd_fifo_in_const_ul <= x"0000";
        upload_const_reg_index <= 0;
        spi_readback_fifo_read_en_const_ul <= '0';
        if (SPI_READ_BUSY='1') then
          const_upload_state <= S_WAIT_READ_STALL;    
        else
          const_upload_state <= S_WAIT_READ_DONE;
        end if;
        
    when S_WAIT_READ_STALL => 
      --need to wait for some reason. FIFO propagation maybe?
      spi_cmd_fifo_write_en_const_ul <= '0';
      spi_const_ul_pulse_inner <= '0';
      spi_const_reg_we_inner <= NREGS;
      spi_const_ul_reg <= SPI_READBACK_FIFO_OUT;
      spi_cmd_fifo_in_const_ul <= x"0000";
      upload_const_reg_index <= 0;
      if (const_readback_fifo_stall_counter=x"0") then
        const_upload_state <= S_READBACK;           
        const_readback_fifo_stall_counter <= x"1F";
        spi_readback_fifo_read_en_const_ul <= '1';
      else
        const_upload_state <= S_WAIT_READ_STALL;
        const_readback_fifo_stall_counter <= const_readback_fifo_stall_counter - 1;
        spi_readback_fifo_read_en_const_ul <= '0';
      end if;
  
    when S_READBACK =>
      spi_cmd_fifo_write_en_const_ul <= '0';
      spi_cmd_fifo_in_const_ul <= x"0000";
      spi_const_ul_pulse_inner <= '1';
      spi_const_reg_we_inner <= upload_const_reg_index;
      spi_const_ul_reg <= SPI_READBACK_FIFO_OUT;
      --read values from readback fifo and send to CFG registers
      spi_cmd_fifo_in_const_ul <= x"0000";
      if (upload_const_reg_index=15) then
        upload_const_reg_index <= 0;
        spi_readback_fifo_read_en_const_ul <= '0';
        const_upload_State <= S_IDLE;
      else
        upload_const_reg_index <= upload_const_reg_index + 1;
        spi_readback_fifo_read_en_const_ul <= '1';
        const_upload_state <= S_READBACK;
      end if;
  
    end case;
  end if;
  end process;


  --multiplex signals to spi_ctrl
  SPI_CMD_FIFO_WRITE_EN <= spi_cmd_fifo_write_en_cmd or spi_cmd_fifo_write_en_cfg_dl or spi_cmd_fifo_write_en_cfg_ul or
                           spi_cmd_fifo_write_en_const_ul or spi_cmd_fifo_write_en_const_dl;
  SPI_CMD_FIFO_IN <= spi_cmd_fifo_in_cfg_dl   when (spi_cmd_fifo_write_en_cfg_dl='1') else 
                     spi_cmd_fifo_in_const_dl when (spi_cmd_fifo_write_en_const_dl='1') else 
                     spi_cmd_fifo_in_cfg_ul   when (spi_cmd_fifo_write_en_cfg_ul='1') else
                     spi_cmd_fifo_in_const_ul when (spi_cmd_fifo_write_en_const_ul='1') else
                     spi_cmd_fifo_in_cmd      when (spi_cmd_fifo_write_en_cmd='1') else
                     x"0000";
  SPI_READBACK_FIFO_READ_EN <= spi_readback_fifo_read_en_cmd or spi_readback_fifo_read_en_cfg_ul or 
                               spi_readback_fifo_read_en_const_ul;

  
  --signals to VMECONFREGS
  SPI_UL_REG         <=  spi_cfg_ul_reg when (spi_cfg_reg_we_inner /= NREGS) else 
                         spi_const_ul_reg when (spi_const_reg_we_inner /= NREGS) else
                         x"0000";
  SPI_CONST_BUSY     <= '0';
  SPI_CFG_BUSY       <= '0';
  SPI_CONST_UL_PULSE <= spi_const_ul_pulse_inner;
  SPI_CONST_REG_WE   <= spi_const_reg_we_inner;
  SPI_CFG_UL_PULSE   <= spi_cfg_ul_pulse_inner;
  SPI_CFG_REG_WE     <= spi_cfg_reg_we_inner;
  
  --TODO: upload registers on reset
  
  -- DTACK: always just issue on second SLOWCLK edge after STROBE
  ce_d_dtack <= strobe_qq and DEVICE;
  FD_D_DTACK : FDCE port map(Q => d_dtack, C => SLOWCLK, CE => ce_d_dtack, CLR => q_dtack, D => '1');
  FD_Q_DTACK : FD port map(Q => q_dtack, C => SLOWCLK, D => d_dtack);
  DTACK    <= q_dtack;
  --FD_D_DTACK : FDCE port map(Q => d_dtack, C => SLOWCLK, CE => ce_d_dtack, CLR => q_dtack, D => '1');
  --FD_Q_DTACK : FD port map(Q => q_dtack, C => SLOWCLK, D => d_dtack);

  --debugging
  DIAGOUT <= "0" & spi_cmd_fifo_in_cmd(11 downto 0) & q_dtack & spi_cmd_fifo_write_en_cmd & STROBE & strobe_pulse & do_spi_cmd;

end SPI_PORT_Arch;
