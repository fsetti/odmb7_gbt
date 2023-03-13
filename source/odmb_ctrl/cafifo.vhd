-- CAFIFO: Handles which data packets are expected and which have arrived. It
-- is a content addressed memory with 3 fields (L1A_CNT, L1A_MATCH, BX_CNT)
-- synchronous with CAFIFO_PUSH (L1A), and the DAVs being filled when the
-- packets have finished arriving.

library ieee;
library work;
library unisim;
library unimacro;
library hdlmacro;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.std_logic_unsigned.all;
use work.ucsb_types.all;
use unisim.vcomponents.all;
use unimacro.vcomponents.all;

entity cafifo is
  generic (
    NCFEB       : integer range 1 to 7   := 7;  -- Number of DCFEBS, 7 in the final design
    CAFIFO_SIZE : integer range 1 to 128 := 128  -- Number of CAFIFO words
    );
  port(

    --CSP_FREE_AGENT_PORT_LA_CTRL : inout std_logic_vector(35 downto 0);
    CLK        : in std_logic;
    DDUCLK     : in std_logic;
    L1ACNT_RST : in std_logic;
    BXCNT_RST  : in std_logic;

    BC0        : in std_logic;
    CCB_BX0    : in std_logic;
    BXRST      : in std_logic;
    BX_DLY     : in integer range 0 to 4095;
    PUSH_DLY   : in integer range 0 to 63;

    l1a          : in std_logic;
    l1a_match_in : in std_logic_vector(NCFEB+2 downto 1);

    pop          : in std_logic;
    eof_data     : in std_logic_vector(NCFEB+2 downto 1);

    cafifo_l1a_match : out std_logic_vector(NCFEB+2 downto 1);
    cafifo_l1a_cnt   : out std_logic_vector(23 downto 0);
    cafifo_l1a_dav   : out std_logic_vector(NCFEB+2 downto 1);
    cafifo_bx_cnt    : out std_logic_vector(11 downto 0);
    cafifo_lost_pckt : out std_logic_vector(NCFEB+2 downto 1);
    cafifo_lone      : out std_logic;

    cafifo_prev_next_l1a_match : out std_logic_vector(15 downto 0);
    cafifo_prev_next_l1a       : out std_logic_vector(15 downto 0);
    control_debug              : in  std_logic_vector(143 downto 0);
    cafifo_debug               : out std_logic_vector(15 downto 0);
    cafifo_wr_addr             : out std_logic_vector(7 downto 0);
    cafifo_rd_addr             : out std_logic_vector(7 downto 0)
    );

end cafifo;


architecture cafifo_architecture of cafifo is

  component fifo_l1acnt_dav
    port (
      clk : in std_logic;
      srst : in std_logic;
      din : in std_logic_vector(23 downto 0);
      wr_en : in std_logic;
      rd_en : in std_logic;
      dout : out std_logic_vector(23 downto 0);
      full : out std_logic;
      empty : out std_logic;
      wr_rst_busy : out std_logic;
      rd_rst_busy : out std_logic
      );
  end component;

  component ila_2 is
    port (
      clk : in std_logic := '0';
      probe0 : in std_logic_vector(383 downto 0) := (others=> '0')
      );
  end component;

  signal wr_addr_en, rd_addr_en                               : std_logic;
  signal cafifo_wren_q, cafifo_rden_q                         : std_logic                        := '0';
  signal wr_addr_out, rd_addr_out, prev_rd_addr, next_rd_addr : integer range 0 to CAFIFO_SIZE-1 := 0;

  signal cafifo_wren, cafifo_rden  : std_logic;
  signal cafifo_empty, cafifo_full : std_logic;

  signal dcfeb_dv : std_logic_vector(NCFEB downto 1);

  type rx_state_type is (RX_IDLE, RX_HEADER1, RX_HEADER2, RX_DW);
  type rx_state_array_type is array (NCFEB+2 downto 1) of rx_state_type;
  signal rx_next_state, rx_current_state : rx_state_array_type;

  signal dcfeb_l1a_dav : std_logic_vector(NCFEB downto 1);

  signal l1a_cnt_out : std_logic_vector(23 downto 0);

  type state_type is (FIFO_EMPTY, FIFO_NOT_EMPTY, FIFO_FULL);
  signal next_state, current_state : state_type;

  type dcfeb_l1a_cnt_array_type is array (NCFEB downto 1) of std_logic_vector(11 downto 0);
  signal dcfeb_l1a_cnt     : dcfeb_l1a_cnt_array_type;
  signal reg_dcfeb_l1a_cnt : dcfeb_l1a_cnt_array_type;

  type ext_dcfeb_l1a_cnt_array_type is array (NCFEB downto 1) of std_logic_vector(23 downto 0);
  signal ext_dcfeb_l1a_cnt : ext_dcfeb_l1a_cnt_array_type;

  type l1a_cnt_array_type is array (CAFIFO_SIZE-1 downto 0) of std_logic_vector(23 downto 0);
  signal l1a_cnt : l1a_cnt_array_type;

  type bx_cnt_array_type is array (CAFIFO_SIZE-1 downto 0) of std_logic_vector(11 downto 0);
  signal bx_cnt : bx_cnt_array_type;

  type l1a_array_type is array (CAFIFO_SIZE-1 downto 0) of std_logic_vector(NCFEB+2 downto 1);
  signal l1a_match          : l1a_array_type;
  signal l1a_dav, lost_pckt : l1a_array_type := ((others => (others => '0')));

  signal l1acnt_dav_fifo_empty, l1acnt_dav_fifo_full  : std_logic_vector(NCFEB+2 downto 1);
  signal l1acnt_dav_fifo_wr_en, l1acnt_dav_fifo_rd_en : std_logic_vector(NCFEB+2 downto 1);

  type fifo_data_array_type is array (NCFEB+2 downto 1) of std_logic_vector(23 downto 0);
  signal l1acnt_dav_fifo_in, l1acnt_dav_fifo_out : fifo_data_array_type;
  signal l1acnt_fifo_rst                         : std_logic := '0';

  -- BX counter
  constant nbx_lhc_orbit : integer := 3564;  -- Number of BX in one LHC orbit
  constant nbx_dmb_odmb  : integer := 2772;  -- Offset between DMB and ODMB measured in some random RAW file
  signal ccb_bx0_delayed : std_logic;

  signal bx_cnt_out             : std_logic_vector(11 downto 0);
  signal bx_cnt_clr             : std_logic;
  signal bx_cnt_int, bx_default : integer range 0 to 3563 := 0;

  type lone_array_type is array (CAFIFO_SIZE-1 downto 0) of std_logic;
  signal lone    : lone_array_type;
  signal lone_in : std_logic;

  type timeout_state is (IDLE, COUNT, WAIT_IDLE);
  type timeout_state_vec is array (NCFEB+2 downto 1) of timeout_state;
  signal timeout_current_state, timeout_next_state : timeout_state_vec;

  type timeout_array is array (NCFEB+2 downto 1) of integer range 0 to 5000;
  signal timeout_cnt   : timeout_array := (0, 0, 0, 0, 0, 0, 0, 0, 0);
  constant timeout_max : timeout_array := (480, 1500, 500, 500, 500, 500, 500, 500, 500);  -- GEM
  --constant timeout_max : timeout_array := (480, 680, 500, 500, 500, 500, 500, 500, 500);  -- Normal length
  --constant timeout_max : timeout_array := (2000, 2000, 2000, 2000, 2000, 2000, 2000, 2000, 2000);  --Debug
  --constant timeout_max : timeout_array := (70, 70, 18, 18, 18, 18, 18, 18, 18);
  -- count to these numbers before
  -- timeout (7 us, 12 us)

  signal timeout_state_1, timeout_state_9 : std_logic_vector(1 downto 0);
  signal timeout_cnt_en, timeout_cnt_rst  : std_logic_vector(NCFEB+2 downto 1);
  signal l1a_dav_en                       : std_logic_vector(NCFEB+2 downto 1);
  signal lost_pckt_en                     : std_logic_vector(NCFEB+2 downto 1);
  signal wait_cnt                         : timeout_array := (0, 0, 0, 0, 0, 0, 0, 0, 0);
  signal wait_cnt_en, wait_cnt_rst        : std_logic_vector(NCFEB+2 downto 1);

  -- Declare the csp stuff here
  signal free_agent_la_data : std_logic_vector(399 downto 0);
  signal free_agent_la_trig : std_logic_vector(19 downto 0);
  constant csp1             : integer := 31;
  constant csp2             : integer := 0;
  constant csp3             : integer := 1;

  signal ila_data : std_logic_vector(383 downto 0);

  -- Regs
  signal lone_in_reg, cafifo_wren_d, lone_in_reg_d, cafifo_wren_dd : std_logic;
  signal l1a_match_in_reg_d, l1a_match_in_reg                      : std_logic_vector(NCFEB+2 downto 1);
  signal bx_cnt_out_reg_d, bx_cnt_out_reg                          : std_logic_vector(11 downto 0);

  -- Out
  signal cafifo_state_slv : std_logic_vector(1 downto 0);

  signal bad_l1a_lone, bad_rdwr_addr                                  : std_logic := '0';
  signal current_l1a_match, current_l1a_match_d, current_l1a_match_dd : std_logic_vector(NCFEB+2 downto 1);
  signal current_l1a_dav, current_lost_pckt                           : std_logic_vector(NCFEB+2 downto 1);
  signal current_bx_cnt                                               : std_logic_vector(11 downto 0);
  signal current_l1a_cnt                                              : std_logic_vector(23 downto 0);
  signal current_lone, current_lone_d, current_lone_dd                : std_logic;
begin

-- Initial assignments

  cafifo_wren_dd <= l1a when (cafifo_full = '0') else '0';
  FDWREND : FD port map(Q => cafifo_wren_d, C => CLK, D => cafifo_wren_dd);
  FDWREN  : FD port map(Q => cafifo_wren, C => CLK, D => cafifo_wren_d);
  --cafifo_wren <= or_reduce(l1a_match_in) when (cafifo_full = '0') else '0';  -- Avoids empty packets
  cafifo_rden    <= pop;

  lone_in <= l1a and not or_reduce(l1a_match_in);

  -- Adding flip-flops to make sure L1A_CNT has updated, and lone_in is synced with L1A_MATCH
  -- Using CROSSCLOCK to cross into the DDU clock domain
  -- Add FDC to LONE and L1A_MATCH to ensure L1A_CNT has been updated in the ODMB header
  FDLONED      : FD port map(Q => lone_in_reg_d, C => CLK, D => lone_in);
  FDLONE       : FD port map(Q => lone_in_reg, C => CLK, D => lone_in_reg_d);
  GEN_L1AM_REG : for dev in 1 to NCFEB+2 generate
    FDL1AMD       : FD port map(Q => l1a_match_in_reg_d(dev), C => CLK, D => l1a_match_in(dev));
    FDL1AM        : FD port map(Q => l1a_match_in_reg(dev),   C => CLK, D => l1a_match_in_reg_d(dev));
    CF_L1AM_FD    : FDC port map(Q => current_l1a_match_d(dev),  C => CLK, CLR => L1ACNT_RST, D => current_l1a_match(dev));
    CF_L1AM_FDD   : FDC port map(Q => current_l1a_match_dd(dev), C => CLK, CLR => L1ACNT_RST, D => current_l1a_match_d(dev));
    CF_L1AM_CROSS : CROSSCLOCK port map(DOUT => CAFIFO_L1A_MATCH(dev), CLK_DOUT => DDUCLK, CLK_DIN => CLK, RST => L1ACNT_RST, DIN => current_l1a_match_dd(dev));
    CF_DAV_CROSS  : CROSSCLOCK port map(DOUT => CAFIFO_L1A_DAV(dev),   CLK_DOUT => DDUCLK, CLK_DIN => CLK, RST => L1ACNT_RST, DIN => current_l1a_dav(dev));
    CF_LOST_CROSS : CROSSCLOCK port map(DOUT => CAFIFO_LOST_PCKT(dev), CLK_DOUT => DDUCLK, CLK_DIN => CLK, RST => L1ACNT_RST, DIN => current_lost_pckt(dev));
  end generate GEN_L1AM_REG;
  GEN_BX_REG : for dev in 0 to 11 generate
    FDL1AMD     : FD port map(Q => bx_cnt_out_reg_d(dev), C => CLK, D => bx_cnt_out(dev));
    FDL1AM      : FD port map(Q => bx_cnt_out_reg(dev),   C => CLK, D => bx_cnt_out_reg_d(dev));
    CF_BX_CROSS : CROSSCLOCK port map(DOUT => CAFIFO_BX_CNT(dev), CLK_DOUT => DDUCLK, CLK_DIN => CLK, RST => L1ACNT_RST, DIN => current_bx_cnt(dev));
  end generate GEN_BX_REG;
  GEN_L1A_REG : for dev in 0 to 23 generate
    CF_L1A_CROSS : CROSSCLOCK port map(DOUT => CAFIFO_L1A_CNT(dev), CLK_DOUT => DDUCLK, CLK_DIN => CLK, RST => L1ACNT_RST, DIN => current_l1a_cnt(dev));
  end generate GEN_L1A_REG;

  current_l1a_match <= l1a_match(rd_addr_out);
  current_bx_cnt    <= bx_cnt(rd_addr_out);
  current_lone      <= lone(rd_addr_out);
  current_l1a_cnt   <= l1a_cnt(rd_addr_out);
  current_l1a_dav   <= l1a_dav(rd_addr_out);
  current_lost_pckt <= lost_pckt(rd_addr_out);

  CF_LONE_FD    : FDC port map(Q => current_lone_d, C => CLK, CLR => L1ACNT_RST, D => current_lone);
  CF_LONE_FDD   : FDC port map(Q => current_lone_dd, C => CLK, CLR => L1ACNT_RST, D => current_lone_d);
  CF_LONE_CROSS : CROSSCLOCK port map(DOUT => CAFIFO_LONE, CLK_DOUT => DDUCLK, CLK_DIN => CLK, RST => L1ACNT_RST, DIN => current_lone_dd);

-------------------- L1A Counter        --------------------

  l1a_counter : process (clk, l1a, l1acnt_rst)
  begin
    if (l1acnt_rst = '1') then
      l1a_cnt_out <= (others => '0');
    elsif (rising_edge(clk)) then
      if (l1a = '1') then
        l1a_cnt_out <= l1a_cnt_out + 1;
      end if;
    end if;
  end process;

---------------------- Memory           ----------------------

  l1a_cnt_fifo : process (cafifo_wren, wr_addr_out, l1acnt_rst, clk, l1a_cnt_out)
  begin
    if (l1acnt_rst = '1') then
      for index in 0 to CAFIFO_SIZE-1 loop
        l1a_cnt(index) <= (others => '1');
      end loop;
    elsif falling_edge(clk) then
      if (cafifo_wren = '1') then
        l1a_cnt(wr_addr_out) <= l1a_cnt_out;
      end if;
      if (cafifo_rden = '1') then
        l1a_cnt(rd_addr_out) <= (others => '1');
      end if;
    end if;
  end process;


  bx_cnt_fifo : process (cafifo_wren, wr_addr_out, bxcnt_rst, clk, bx_cnt_out_reg)
  begin
    if (bxcnt_rst = '1') then
      for index in 0 to CAFIFO_SIZE-1 loop
        bx_cnt(index) <= (others => '0');
      end loop;
    elsif falling_edge(clk) then
      if (cafifo_wren = '1') then
        bx_cnt(wr_addr_out) <= bx_cnt_out_reg(11 downto 0);
      end if;
    end if;
  end process;


  l1a_match_fifo : process (cafifo_wren, wr_addr_out, l1acnt_rst, clk, l1a_match_in_reg)
  begin
    if l1acnt_rst = '1' then
      for index in 0 to CAFIFO_SIZE-1 loop
        l1a_match(index) <= (others => '0');
      end loop;
    elsif falling_edge(clk) then
      if (cafifo_wren = '1') then
        l1a_match(wr_addr_out) <= l1a_match_in_reg;
      end if;
      if (cafifo_rden = '1') then
        l1a_match(rd_addr_out) <= (others => '0');
      end if;
    end if;
  end process;


  lone_fifo : process (cafifo_wren, wr_addr_out, l1acnt_rst, clk, lone_in_reg)
  begin
    if l1acnt_rst = '1' then
      for index in 0 to CAFIFO_SIZE-1 loop
        lone(index) <= '0';
      end loop;
    elsif falling_edge(clk) then
      if (cafifo_wren = '1') then
        lone(wr_addr_out) <= lone_in_reg;
      end if;
      if (cafifo_rden = '1') then
        lone(rd_addr_out) <= '0';
      end if;
    end if;
  end process;


--------------------------- GENERATE DAVS and LOSTS  -------------------------------

  L1ARESETPULSE  : NPULSE2SAME port map(DOUT => l1acnt_fifo_rst, CLK_DOUT => CLK, RST => '0', NPULSE => 5, DIN => l1acnt_rst);
  GEN_L1ACNT_DAV : for dev in 1 to NCFEB+2 generate
    l1acnt_dav_fifo_wr_en(dev) <= l1a_match_in_reg(dev);
    l1acnt_dav_fifo_in(dev)    <= l1a_cnt_out;
    --FIFORD       : FD port map(l1acnt_dav_fifo_rd_en(dev), clk, l1acnt_dav_fifo_rd_en_d(dev));
  L1ACNT_DAV_FIFO_I : fifo_l1acnt_dav
  PORT MAP (
      clk => clk,
      srst => l1acnt_fifo_rst,
      din => l1acnt_dav_fifo_in(dev),
      wr_en => l1acnt_dav_fifo_wr_en(dev),
      rd_en => l1acnt_dav_fifo_rd_en(dev),
      dout => l1acnt_dav_fifo_out(dev),
      full => l1acnt_dav_fifo_full(dev),
      empty => l1acnt_dav_fifo_empty(dev),
      wr_rst_busy => open,
      rd_rst_busy => open 
  );
  end generate GEN_L1ACNT_DAV;

  DAV_LOST_PRO : process(L1ACNT_RST, CLK, cafifo_rden, rd_addr_out, l1a_dav_en, lost_pckt_en)
  begin
    for dev in 1 to NCFEB+2 loop
      for index in 0 to CAFIFO_SIZE-1 loop
        if (l1acnt_rst = '1' or (cafifo_rden = '1' and index = rd_addr_out)) then
          l1a_dav(index)(dev)   <= '0';
          lost_pckt(index)(dev) <= '0';
        elsif rising_edge(CLK) then
          if (l1acnt_dav_fifo_out(dev) = l1a_cnt(index) and l1a_dav_en(dev) = '1') then
            l1a_dav(index)(dev) <= '1';
          end if;
          if (l1acnt_dav_fifo_out(dev) = l1a_cnt(index) and lost_pckt_en(dev) = '1') then
            lost_pckt(index)(dev) <= '1';
          end if;
        end if;
      end loop;
    end loop;
  end process;


  -- Timeouts handled by this FSM
  timeout_fsm_regs : process (timeout_next_state, L1ACNT_RST, CLK, timeout_cnt_en,
                              timeout_cnt_rst, wait_cnt_en, wait_cnt_rst)
  begin
    for dev in 1 to NCFEB+2 loop
      if (L1ACNT_RST = '1') then
        timeout_cnt(dev)           <= 0;
        timeout_current_state(dev) <= IDLE;
        wait_cnt(dev)              <= 0;
      elsif rising_edge(CLK) then
        timeout_current_state(dev) <= timeout_next_state(dev);
        if (timeout_cnt_rst(dev) = '1') then
          timeout_cnt(dev) <= 0;
        elsif(timeout_cnt_en(dev) = '1') then
          timeout_cnt(dev) <= timeout_cnt(dev) +1;
        end if;
        if (wait_cnt_rst(dev) = '1') then
          wait_cnt(dev) <= 0;
        elsif (wait_cnt_en(dev) = '1') then
          wait_cnt(dev) <= wait_cnt(dev)+1;
        end if;
      end if;
    end loop;
  end process;

  timeout_fsm_logic : process (timeout_current_state, timeout_cnt, eof_data,
                               l1acnt_dav_fifo_empty, wait_cnt)
  begin
    for dev in 1 to NCFEB+2 loop
      timeout_cnt_en(dev)        <= '0';
      timeout_cnt_rst(dev)       <= '0';
      lost_pckt_en(dev)          <= '0';
      l1a_dav_en(dev)            <= '0';
      l1acnt_dav_fifo_rd_en(dev) <= '0';
      wait_cnt_en(dev)           <= '0';
      wait_cnt_rst(dev)          <= '0';

      case timeout_current_state(dev) is
        when IDLE =>
          wait_cnt_rst(dev) <= '1';
          if (l1acnt_dav_fifo_empty(dev) = '0') then
            timeout_next_state(dev) <= COUNT;
          else
            timeout_next_state(dev) <= IDLE;
          end if;
        when COUNT =>
          timeout_cnt_en(dev) <= '1';
          if (eof_data(dev) = '1' or timeout_cnt(dev) = timeout_max(dev)) then
            timeout_next_state(dev) <= WAIT_IDLE;
            if (eof_data(dev) = '1') then
              l1a_dav_en(dev) <= '1';
            else
              lost_pckt_en(dev) <= '1';
            end if;
          else
            timeout_next_state(dev) <= COUNT;
          end if;
        when WAIT_IDLE =>
          timeout_cnt_rst(dev) <= '1';
          wait_cnt_en(dev)     <= '1';
          if (wait_cnt(dev) = 1) then
            l1acnt_dav_fifo_rd_en(dev) <= '1';
          end if;
          if (wait_cnt(dev) = 3) then
            timeout_next_state(dev) <= IDLE;
          else
            timeout_next_state(dev) <= WAIT_IDLE;
          end if;
      end case;
    end loop;
  end process;

  timeout_state_1 <= "01" when timeout_current_state(1) = IDLE else
                     "10" when timeout_current_state(1) = COUNT else
                     "11" when timeout_current_state(1) = WAIT_IDLE else
                     "00";
  timeout_state_9 <= "01" when timeout_current_state(2) = IDLE else
                     "10" when timeout_current_state(2) = COUNT else
                     "11" when timeout_current_state(2) = WAIT_IDLE else
                     "00";

-----------------------------------------------------------------------------------------


-- Address Counters

  FD_WREN : FDC port map(Q => cafifo_wren_q, C => CLK, CLR => L1ACNT_RST, D => cafifo_wren);
  FD_RDEN : FDC port map(Q => cafifo_rden_q, C => CLK, CLR => L1ACNT_RST, D => cafifo_rden);

  addr_counter : process (clk, wr_addr_en, rd_addr_en, l1acnt_rst)
  begin
    if (l1acnt_rst = '1') then
      rd_addr_out <= 0;
      wr_addr_out <= 0;
    elsif (rising_edge(clk)) then
      if (wr_addr_en = '1') then
        if (wr_addr_out = CAFIFO_SIZE-1) then
          wr_addr_out <= 0;
        else
          wr_addr_out <= wr_addr_out + 1;
        end if;
      end if;
      if (rd_addr_en = '1') then
        if (rd_addr_out = CAFIFO_SIZE-1) then
          rd_addr_out <= 0;
        else
          rd_addr_out <= rd_addr_out + 1;
        end if;
      end if;
    end if;
  end process;

-- FSM
  fsm_regs : process (next_state, l1acnt_rst, clk)
  begin
    if (l1acnt_rst = '1') then
      current_state <= FIFO_EMPTY;
    elsif rising_edge(clk) then
      current_state <= next_state;
    end if;
  end process;

  fsm_logic : process (cafifo_wren_q, cafifo_rden_q, current_state, wr_addr_out, rd_addr_out)
  begin
    case current_state is
      when FIFO_EMPTY =>
        cafifo_empty <= '1';
        cafifo_full  <= '0';
        if (cafifo_wren_q = '1') then
          next_state <= FIFO_NOT_EMPTY;
          wr_addr_en <= '1';
          rd_addr_en <= '0';
        else
          next_state <= FIFO_EMPTY;
          wr_addr_en <= '0';
          rd_addr_en <= '0';
        end if;

      when FIFO_NOT_EMPTY =>
        cafifo_empty <= '0';
        cafifo_full  <= '0';
        if (cafifo_wren_q = '1' and cafifo_rden_q = '0') then
          if ((wr_addr_out = rd_addr_out-1) or (wr_addr_out = CAFIFO_SIZE-1 and rd_addr_out = 0)) then
            next_state <= FIFO_FULL;
          else
            next_state <= FIFO_NOT_EMPTY;
          end if;
          wr_addr_en <= '1';
          rd_addr_en <= '0';
        elsif (cafifo_rden_q = '1' and cafifo_wren_q = '0') then
          if (rd_addr_out = wr_addr_out-1 or (rd_addr_out = CAFIFO_SIZE-1 and wr_addr_out = 0)) then
            next_state <= FIFO_EMPTY;
          else
            next_state <= FIFO_NOT_EMPTY;
          end if;
          rd_addr_en <= '1';
          wr_addr_en <= '0';
        elsif (cafifo_rden_q = '1' and cafifo_wren_q = '1') then
          next_state <= FIFO_NOT_EMPTY;
          wr_addr_en <= '1';
          rd_addr_en <= '1';
        else
          next_state <= FIFO_NOT_EMPTY;
          wr_addr_en <= '0';
          rd_addr_en <= '0';
        end if;

      when FIFO_FULL =>
        cafifo_empty <= '0';
        cafifo_full  <= '1';
        wr_addr_en   <= '0';
        if (cafifo_rden_q = '1') then
          next_state <= FIFO_NOT_EMPTY;
          rd_addr_en <= '1';
        else
          next_state <= FIFO_FULL;
          rd_addr_en <= '0';
        end if;

      when others =>
        next_state   <= FIFO_EMPTY;
        cafifo_empty <= '0';
        cafifo_full  <= '0';
        wr_addr_en   <= '0';
        rd_addr_en   <= '0';

    end case;
  end process;

  cafifo_state_slv <= "01" when current_state = FIFO_EMPTY else
                      "10" when current_state = FIFO_NOT_EMPTY else
                      "11" when current_state = FIFO_FULL else
                      "00";

  cafifo_debug <= cafifo_empty & cafifo_full & cafifo_state_slv & timeout_state_1 & timeout_state_9
                  & lone(rd_addr_out) & lost_pckt(rd_addr_out)(8 downto 2);

  prev_rd_addr               <= rd_addr_out-1 when rd_addr_out > 0             else CAFIFO_SIZE-1;
  next_rd_addr               <= rd_addr_out+1 when rd_addr_out < CAFIFO_SIZE-1 else 0;
  cafifo_prev_next_l1a_match <= l1a_match(prev_rd_addr)(8 downto 1) & l1a_match(next_rd_addr)(8 downto 1);
  cafifo_prev_next_l1a       <= l1a_cnt(prev_rd_addr)(7 downto 0) & l1a_cnt(next_rd_addr)(7 downto 0);

  bad_l1a_lone <= not or_reduce(l1a_match_in_reg) and not lone_in_reg and cafifo_wren;
  bad_rdwr_addr <= '1' when (rd_addr_out /= wr_addr_out and or_reduce(l1a_match(rd_addr_out)) = '0'
                             and cafifo_rden = '0'
                             and lone(rd_addr_out) = '0' and rd_addr_en = '0' and rd_addr_en = '0') else '0';

  free_agent_la_trig <= or_reduce(lost_pckt_en(7 downto 1)) & or_reduce(current_lost_pckt(7 downto 1)) &
                        bad_l1a_lone & bad_rdwr_addr & cafifo_full & control_debug(9) & cafifo_wren & cafifo_rden &
                        std_logic_vector(to_unsigned(rd_addr_out, 6)) &
                        std_logic_vector(to_unsigned(wr_addr_out, 6));
  free_agent_la_data <= x"0000000000" & x"0000"
                        & control_debug
                        & l1acnt_dav_fifo_out(1)(4 downto 0)    -- [199:195]
                        & wait_cnt_en(2) & wait_cnt_rst(2)  -- [194:193]
                        & timeout_state_9  -- [192:191]
                        & cafifo_state_slv & timeout_cnt_en(1)  -- [190:188]
                        & timeout_state_1  -- [187:186]
                        & wait_cnt_en(1) & wait_cnt_rst(1)  -- [185:184]
                        & l1a_dav_en(1) & l1acnt_dav_fifo_rd_en(1)  -- [183:182]
                        & lost_pckt_en(1) & timeout_cnt_en(1) & timeout_cnt_rst(1)  -- [181:179]
                        & l1a_dav_en(9 downto 1) & lost_pckt(prev_rd_addr)  -- [178:161]
                        & lost_pckt(next_rd_addr) & lost_pckt(rd_addr_out)  -- [160:143]
                        & lone_in_reg & cafifo_wren & cafifo_rden & wr_addr_en & rd_addr_en  -- [142:138]
                        & l1a_cnt_out(3 downto 0)       -- [137:134]
                        & l1a_dav(prev_rd_addr)  -- [133:125]
                        & l1a_dav(next_rd_addr) & l1a_dav(rd_addr_out)  -- [124:107]
                        & lost_pckt_en(8 downto 1)      -- [106:99]
                        & bad_rdwr_addr & l1a_match(prev_rd_addr)   -- [98:89]
                        & l1a_match(next_rd_addr) & l1a_match(rd_addr_out)  -- [88:71]
                        & bad_l1a_lone & lone(prev_rd_addr) & lone(next_rd_addr) & lone(rd_addr_out)  -- [70:67]
                        & l1a_cnt(prev_rd_addr)(3 downto 0)     -- [66:63]
                        & l1a_cnt(next_rd_addr)(3 downto 0) & l1a_cnt(rd_addr_out)(3 downto 0)  -- [62:55]
                        & EOF_DATA      -- [54:46]
                        -- & ALCT_DV & OTMB_DV & dcfeb_dv  -- [45:37]
                        -- & DCFEB3_DATA(15 downto 12) & DCFEB2_DATA(15 downto 12)  -- [36:29]
                        -- & DCFEB1_DATA(15 downto 12) & DCFEB0_DATA(15 downto 12)  -- [28:21]
                        & '0' & x"00"    -- [45:37]
                        & BC0 & BXRST & ccb_bx0_delayed & bx_cnt_clr -- [36:33]
                        & bx_cnt_out -- [32:21]
                        & L1A_MATCH_IN & L1A & POP      -- [20:10]
                        & std_logic_vector(to_unsigned(wr_addr_out, 5))  -- [9:5]
                        & std_logic_vector(to_unsigned(rd_addr_out, 5));  -- [4:0]
  
  cafifo_wr_addr <= std_logic_vector(to_unsigned(wr_addr_out, cafifo_wr_addr'length));
  cafifo_rd_addr <= std_logic_vector(to_unsigned(rd_addr_out, cafifo_rd_addr'length));

  -- dcfeb_dv <= dcfeb6_dv & dcfeb5_dv & dcfeb4_dv & dcfeb3_dv & dcfeb2_dv & dcfeb1_dv & dcfeb0_dv;

  -- Generate BX_CNT
  DS_BX0_PUSH : DELAY_SIGNAL port map(DOUT => ccb_bx0_delayed, CLK => CLK, NCYCLES => PUSH_DLY, DIN => CCB_BX0);
  bx_cnt_clr <= BC0 or BXRST or ccb_bx0_delayed;
  -- bx_default <= NBX_DMB_ODMB + BX_DLY when NBX_DMB_ODMB + BX_DLY < NBX_LHC_ORBIT else
  --               NBX_DMB_ODMB + BX_DLY - NBX_LHC_ORBIT when BX_DLY < NBX_LHC_ORBIT else
  --               NBX_DMB_ODMB;  -- bx_dly set to 0 if greater than nbx_lhc_orbit
  bx_cnt_proc : process (CLK, bx_cnt_clr)
  begin
    if rising_edge(CLK) then
      if bx_cnt_clr = '1' then
        -- bx_cnt_int <= bx_default;
        bx_cnt_int <= 0;
      elsif bx_cnt_int = NBX_LHC_ORBIT-1 then
        bx_cnt_int <= 0;
      else
        bx_cnt_int <= bx_cnt_int + 1;
      end if;
    end if;
  end process;
  bx_cnt_out <= std_logic_vector(to_unsigned(bx_cnt_int, 12));

  ila_data <= free_agent_la_data(383 downto 0);
  ila_cafifo_inst : ila_2
    port map(
      clk => DDUCLK,
      probe0 => ila_data
      );

end cafifo_architecture;
