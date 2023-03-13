------------------------------------------------------------------------
--    Disclaimer:  XILINX IS PROVIDING THIS DESIGN, CODE, OR
--                 INFORMATION "AS IS" SOLELY FOR USE IN DEVELOPING
--                 PROGRAMS AND SOLUTIONS FOR XILINX DEVICES.  BY
--                 PROVIDING THIS DESIGN, CODE, OR INFORMATION AS
--                 ONE POSSIBLE IMPLEMENTATION OF THIS FEATURE,
--                 APPLICATION OR STANDARD, XILINX IS MAKING NO
--                 REPRESENTATION THAT THIS IMPLEMENTATION IS FREE
--                 FROM ANY CLAIMS OF INFRINGEMENT, AND YOU ARE
--                 RESPONSIBLE FOR OBTAINING ANY RIGHTS YOU MAY
--                 REQUIRE FOR YOUR IMPLEMENTATION.  XILINX
--                 EXPRESSLY DISCLAIMS ANY WARRANTY WHATSOEVER WITH
--                 RESPECT TO THE ADEQUACY OF THE IMPLEMENTATION,
--                 INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OR
--                 REPRESENTATIONS THAT THIS IMPLEMENTATION IS FREE
--                 FROM CLAIMS OF INFRINGEMENT, IMPLIED WARRANTIES
--                 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
--                 PURPOSE.
-- 
--                 (c) Copyright 2013-2016 Xilinx, Inc.
--                 All rights reserved.
------------------------------------------------------------------------

-- R.K.
library ieee;
Library UNISIM;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
use UNISIM.vcomponents.all;

use work.Firmware_pkg.all;     -- for switch between sim and synthesis

entity spiflashprogrammer_test is
  port
  (
    Clk           : in  std_logic;
    fifoclk       : in std_logic;
    ------------------------------------
    data_to_fifo  : in std_logic_vector(15 downto 0);
    startaddr     : in std_logic_vector(31 downto 0);
    startaddrvalid   : in std_logic;
    pagecount     : in std_logic_vector(17 downto 0);   
    pagecountvalid   : in std_logic;
    sectorcount   : in std_logic_vector(13 downto 0);
    sectorcountvalid : in std_logic;
    --------------------------------
    fifowren      : in std_logic;
    fifofull      : out std_logic;
    fifoempty     : out std_logic;
    fifoafull     : out std_logic;
    fifowrerr     : out std_logic;
    fiforderr     : out std_logic;
    writedone     : out std_logic;
    ----------------------------------
    reset         : in std_logic;
    read          : in std_logic;
    readdone      : out std_logic;
    write         : in std_logic;
    erase         : in std_logic;
    eraseing      : out std_logic;
    erasedone     : out std_logic;
    ------------------------------------
    write_nwords : in unsigned(11 downto 0);
    ------------------------------------
    startwrite   : out std_logic;
    out_read_inprogress        : out std_logic;
    out_rd_SpiCsB: out std_logic;
    out_SpiCsB_N: out std_logic;
    out_read_start: out std_logic;
    out_SpiMosi: out std_logic;
    out_SpiMiso: out std_logic;
    out_CmdSelect: out std_logic_vector(7 downto 0);
    in_CmdIndex: in std_logic_vector(3 downto 0);
    in_rdAddr: in std_logic_vector(31 downto 0);
    in_wdlimit: in std_logic_vector(31 downto 0);
    out_SpiCsB_FFDin: out std_logic;
    out_rd_data_valid_cntr: out std_logic_vector(3 downto 0);
    out_rd_data_valid: out std_logic;
    out_nword_cntr: out std_logic_vector(31 downto 0);
    out_cmdreg32: out std_logic_vector(39 downto 0);
    out_cmdcntr32: out std_logic_vector(5 downto 0);
    out_rd_rddata: out std_logic_vector(15 downto 0);
    out_rd_rddata_all: out std_logic_vector(15 downto 0);
    out_er_status: out std_logic_vector(1 downto 0);
    out_wr_rddata: out std_logic_vector(1 downto 0);
    out_wr_statusdatavalid: out std_logic;
    out_wr_spistatus: out std_logic_vector(1 downto 0);
    out_wrfifo_dout: out std_logic_vector(3 downto 0);
    out_wrfifo_rden: out std_logic
   ); 	
end spiflashprogrammer_test;
architecture behavioral of spiflashprogrammer_test is
  attribute mark_debug : string;
  attribute dont_touch : string;
  attribute keep : string;
  attribute shreg_extract : string;
  attribute async_reg     : string;
  
component SpiCsBflop is
  port (
    C : in  std_logic;
    D : in std_logic;
    Q : out std_logic
  );
end component SpiCsBflop;

component oneshot is
port (
  trigger: in  std_logic;
  clk : in std_logic;
  pulse: out std_logic
);
end component oneshot;
 
COMPONENT writeSpiFIFO
  PORT (
      srst : IN STD_LOGIC;
      wr_clk : IN STD_LOGIC;
      rd_clk : IN STD_LOGIC;
      din : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
      wr_en : IN STD_LOGIC;
      rd_en : IN STD_LOGIC;
      dout : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
      full : OUT STD_LOGIC;
      empty : OUT STD_LOGIC;
      prog_full : OUT STD_LOGIC;
      wr_rst_busy : OUT STD_LOGIC;
      rd_rst_busy : OUT STD_LOGIC
        );
END COMPONENT;

  -- SPI COMMAND ADDRESS WIDTH (IN BITS): Ensure setting is correct for the target flash
  constant  AddrWidth        : integer   := 32;  -- 24 or 32 (3 or 4 byte addr mode)
  -- SPI SECTOR SIZE (IN Bits)
  constant  SectorSize       : integer := 65536; -- 64K bits
  constant  SizeSector       : std_logic_vector(31 downto 0) := X"00010000"; -- 65536 bits
  constant  SubSectorSize    : integer := 4096; -- 4K bits
  constant  SizeSubSector    : std_logic_vector(31 downto 0) := X"00001000"; -- 4K bits
  constant  NumberofSectors  : std_logic_vector(8 downto 0) := "000000000";  -- 512 Sectors total
  constant  PageSize         : std_logic_vector(31 downto 0) := X"00000100"; -- 
  constant  NumberofPages    : std_logic_vector(16 downto 0) := "10000000000000000"; -- 256 bytes pages = 20000h
  constant  AddrStart32      : std_logic_vector(31 downto 0) := X"00000000"; -- First address in SPI
  constant  AddrEnd32        : std_logic_vector(31 downto 0) := X"01FFFFFF"; -- Last address in SPI (256Mb)
  -- SPI flash information
  constant  Idcode25NQ256    : std_logic_vector(23 downto 0) := X"20BB19";  -- RDID N256Q 256 MB
  
  -- Device command opcodes
  constant  CmdREAD24        : std_logic_vector(7 downto 0)  := X"03";
  constant  CmdFASTREAD      : std_logic_vector(7 downto 0)  := X"0B";
  constant  CmdREAD32        : std_logic_vector(7 downto 0)  := X"13";
  constant  CmdRDID          : std_logic_vector(7 downto 0)  := X"9F";
  constant  CmdRDFlashPara   : std_logic_vector(7 downto 0)  := X"5A";
  constant  CmdRDFR24Quad    : std_logic_vector(7 downto 0)  := X"0C";
  constant  CmdFLAGStatus    : std_logic_vector(7 downto 0)  := X"70";
  constant  CmdStatus        : std_logic_vector(7 downto 0)  := X"05";
  constant  CmdWE            : std_logic_vector(7 downto 0)  := X"06";
  constant  CmdSE24          : std_logic_vector(7 downto 0)  := X"D8";
  constant  CmdSE32          : std_logic_vector(7 downto 0)  := X"DC";
  constant  CmdSSE24         : std_logic_vector(7 downto 0)  := X"20";
  constant  CmdSSE32         : std_logic_vector(7 downto 0)  := X"21";
  constant  CmdPP24          : std_logic_vector(7 downto 0)  := X"02";
  constant  CmdPP32          : std_logic_vector(7 downto 0)  := X"12";
  constant  CmdPP24Quad      : std_logic_vector(7 downto 0)  := X"32"; 
  constant  CmdPP32Quad      : std_logic_vector(7 downto 0)  := X"34"; 
  constant  Cmd4BMode        : std_logic_vector(7 downto 0)  := X"B7";
  constant  CmdExit4BMode    : std_logic_vector(7 downto 0)  := X"E9";

   ------------- select read command and address -------------------- 
   signal CmdIndex    : std_logic_vector(3 downto 0) := "0001";  
   signal CmdSelect    : std_logic_vector(7 downto 0) := x"FF";  
   signal AddSelect: std_logic_vector(31 downto 0) := x"00000000";  -- 32 bit command/addr
   ------------- other signals/regs/counters  ------------------------
   signal cmdcounter32    : std_logic_vector(5 downto 0) := "100111";  -- 32 bit command/addr
   signal cmdreg32        : std_logic_vector(39 downto 0) := X"1111111111";  -- avoid LSB removal
   signal data_valid_cntr : std_logic_vector(2 downto 0) := "000";
   signal rddata          : std_logic_vector(1 downto 0) := "00";
   signal wrdata_count    : std_logic_vector(2 downto 0) := "000"; -- SPI from FIFO Nibble count
   signal spi_wrdata      : std_logic_vector(31 downto 0) := X"00000000";
   signal page_count      : std_logic_vector(17 downto 0) := "111111111111111111";
   signal Current_Addr    : std_logic_vector(31 downto 0) := X"00000000";
   signal StatusDataValid : std_logic := '0';
   signal spi_status      : std_logic_vector(1 downto 0) := "11";
   signal write_done : std_logic := '0';
   signal write_nwords_limit : unsigned(13 downto 0) := (others => '0');
      ------- erase ----------------------------
   signal er_sector_count          : std_logic_vector(13 downto 0) := "00000000000001";    -- subsector count
   signal er_current_sector_addr   : std_logic_vector(31 downto 0) := X"00000000"; -- start addr of current sector
   signal er_SpiCsB       : std_logic;
   signal erase_start     : std_logic := '0';
   signal er_data_valid_cntr       : std_logic_vector(2 downto 0) := "000";
   signal er_cmdcounter32 : std_logic_vector(5 downto 0) := "111111";  -- 32 bit command/addr
   signal er_rddata       : std_logic_vector(1 downto 0) := "00";
   signal er_cmdreg32     : std_logic_vector(39 downto 0) := X"1111111111";  -- avoid LSB removal
   signal er_status       : std_logic_vector(1 downto 0) := "11";
   signal erase_inprogress: std_logic := '0';
   signal erase_done: std_logic := '0';
      ------- read ----------------------------
   signal rd_SpiCsB       : std_logic;
   signal read_start     : std_logic := '0';
   signal read_done      : std_logic := '1';
   signal rd_data_valid       : std_logic := '0';
   signal rd_data_valid_cntr       : std_logic_vector(3 downto 0) := "0000";
   signal rd_current_sector_addr   : std_logic_vector(31 downto 0) := X"00000000"; -- start addr of current sector
   -- count 1 page for now
   signal rd_nword_limit       : std_logic_vector(31 downto 0) := x"00000000";
   signal rd_nword_cntr       : std_logic_vector(31 downto 0) := x"00000000";
   signal rd_nword_cntr_dly       : std_logic_vector(31 downto 0) := x"00000000";
   signal rd_data_wait_clk       : integer := 48;
   signal rd_cmdcounter32 : std_logic_vector(5 downto 0) := "111111";  -- 32 bit command/addr
   signal rd_rddata       : std_logic_vector(15 downto 0) := X"0000";
   signal rd_rddata_all       : std_logic_vector(15 downto 0) := X"0000";
   signal rd_cmdreg32     : std_logic_vector(39 downto 0) := X"1111111111";  -- avoid LSB removal
   signal read_inprogress: std_logic := '0';
      ------------ StartupE2 signals  ---------------------------
   signal SpiMiso         : std_logic;
   signal SpiMosi         : std_logic;
   signal SpiCsB          : std_logic := '1';
   signal SpiCsB_N        : std_logic;
   signal SpiCsB_FFDin    : std_logic := '1';
   signal di_out          : std_logic_vector(3 downto 0) := X"0";
   signal do_in           : std_logic_vector(3 downto 0) := (others => '0');
   signal dopin_ts        : std_logic_vector(3 downto 0) := "1110";
   signal SpiMosi_int     : std_logic;
   ----------- FIFO signals  ---------------------
   signal fifo_rden       : std_logic := '0';
   signal fifo_empty      : std_logic := '0';
   signal fifo_full       : std_logic := '0';
   signal fifo_almostfull : std_logic := '0';
   signal fifo_almostempty : std_logic := '0';
   signal fifodout        : std_logic_vector(63 downto 0) := X"0000000000000000";
   signal fifo_unconned   : std_logic_vector(15 downto 0) := X"0000";
   ----- Misc signal
   signal reset_design    : std_logic := '0';
   signal wrerr           : std_logic := '0';
   signal rderr           : std_logic := '0';
   ----  syncers
   ----  place sync regs close together and no SRLs
   signal synced_fifo_almostfull : std_logic_vector(1 downto 0) := "00";
     attribute keep of synced_fifo_almostfull : signal is "true";
     attribute async_reg of synced_fifo_almostfull : signal is "true";   
     attribute shreg_extract of synced_fifo_almostfull : signal is "no";

   signal synced_read : std_logic_vector(1 downto 0) := "00";
     attribute keep of synced_read : signal is "true";
     attribute async_reg of synced_read : signal is "true";   
     attribute shreg_extract of synced_read : signal is "no";

   signal synced_erase : std_logic_vector(1 downto 0) := "00";
     attribute keep of synced_erase : signal is "true";
     attribute async_reg of synced_erase : signal is "true";   
     attribute shreg_extract of synced_erase : signal is "no";

     type erstates is
   (
     S_ER_IDLE, S_S4BMode_ASSCS1, S_S4BMode_WRCMD, S_S4BMode_ASSCS2, S_S4BMode_WR4BADDR, 
     S_ER_ASSCS1, S_ER_ASSCS2, S_ER_ASSCS3, S_ER_WRCMD, S_ER_ERASECMD, S_ER_RDSTAT   --  
   );
   signal erstate  : erstates := S_ER_IDLE;

     type wrstates is
   (
     S_WR_IDLE, S_WR_ASSCS1, S_WR_WRCMD,  S_WR_S4BMode_ASSCS1, S_WR_S4BMode_WRCMD,S_WR_S4BMode_ASSCS2, S_WR_S4BMode_WR4BADDR,
     S_WR_ASSCS2, S_WR_PROGRAM, S_WR_DATA, S_WR_PPDONE, S_WR_PPDONEPRE, S_WR_PPDONESTATUS, S_WR_PPDONE_WAIT , S_EXIT4BMode_ASSCS1, S_EXIT4BMODE
   );
   signal wrstate  : wrstates := S_WR_IDLE;

     type rdstates is
   (
     S_RD_IDLE, S_RD_S4BMode_ASSCS1, S_RD_S4BMode_WRCMD,S_RD_S4BMode_ASSCS2,S_RD_S4BMode_WR4BADDR, S_RD_CS1, S_RD_RDCMD, S_RD_EXIT4BMode_ASSCS1, S_RD_EXIT4BMode 
   );
   signal rdstate  : rdstates := S_RD_IDLE;

 begin

  do_in <= fifodout(3 downto 1) & SpiMosi;
  STARTUPE3_inst : STARTUPE3
  port map (
          CFGCLK => open,
          CFGMCLK => open,
          EOS => open,
          DI => di_out,  -- inSpiMiso D01 pin to Fabric
          PREQ => open,
          -- End outputs to fabric ports
          DO => do_in,
          DTS => dopin_ts,
          FCSBO => SpiCsB_N,
          FCSBTS =>  '0',
          GSR => '0',
          GTS => '0',
          KEYCLEARB => '1',
          PACK => '1',
          USRCCLKO => Clk,
          USRCCLKTS => '0',  -- Clk_ts,
          USRDONEO => '1',
          USRDONETS => '0'    
  );
  
  SpiMiso <= di_out(1);  -- Synonym 
 
  out_wrfifo_dout <= fifodout(3 downto 0); 
 
  negedgecs_flop : SpiCsBflop    -- launch SpicCsB on neg edge
    port map (
            C => Clk,
            D => SpiCsB_FFDin,  
            Q => SpiCsB_N   
    );

  --process (clk)
  --begin
  --    if falling_edge(clk) then
  --        SpiCsB_N <= SpiCsB_FFDin;
  --        --SpiCsB_N <= rd_SpiCsB;

  --    end if;
  --end process;
    
  oneshot_inst_rd  : oneshot
      port map (
        trigger  => synced_read(0),
        clk   => Clk,
        pulse  => read_start
      );

  oneshot_inst_er  : oneshot
      port map (
        trigger  => synced_erase(0),
        clk   => Clk,
        pulse  => erase_start
      );

--FIFO36_inst : FIFO36E2
--           generic map (
--              CLOCK_DOMAINS => "INDEPENDENT",     -- COMMON, INDEPENDENT
--              FIRST_WORD_FALL_THROUGH => "TRUE",  -- first word read doesn't require FIFO_EN
--              PROG_EMPTY_THRESH => 2,             -- 
--              PROG_FULL_THRESH => 65,             -- Async case. Top level artifect. Usually set to 64 
--              READ_WIDTH => 4,                    -- 
--              REGISTER_MODE => "REGISTERED",      -- 
--              RSTREG_PRIORITY => "RSTREG",        -- REGCE, RSTREG
--              WRITE_WIDTH => 36                    
--           )    
--           port map (
--              CASDOUT => open,             
--              CASDOUTP => open,           
--              CASNXTEMPTY => open,    
--              CASPRVRDEN => open,       
--              DOUT => fifodout,                   
--              DOUTP => open,                 
--              EMPTY => fifo_empty,                 
--              FULL => fifo_full,                   
--              PROGEMPTY => fifo_almostempty,         
--              PROGFULL => fifo_almostfull,           
--              RDCOUNT => open,             
--              RDERR => open,                 
--              RDRSTBUSY => open,         
--              WRCOUNT => open,             
--              WRERR => wrerr,                 
--              WRRSTBUSY => open,         
--              CASDIN => X"0000000000000000",               
--              CASDINP => X"00",             
--              CASDOMUX => '0',           
--              CASDOMUXEN => '1',       
--              CASNXTRDEN => '0',       
--              CASOREGIMUX => '0',                  
--              CASOREGIMUXEN => '1', 
--              CASPRVEMPTY => '0',     
--              RDCLK => Clk,                 
--              RDEN => fifo_rden, 
--              REGCE => '1',                 
--              RSTREG => '0',               
--              SLEEP => '0',                 
--              RST => reset_design,    -- Requires a WRCLK                    
--              WRCLK => fifoclk,       -- DRCK cable clock frequency          
--              WREN => fifowren,                   
--              DIN => fifo_unconned,                      
--              DINP => X"00",
--              INJECTDBITERR => '0',
--              INJECTSBITERR =>  '0',
--              DBITERR => open,
--              SBITERR => open,
--              ECCPARITY => open
--           );
writeFIFO_i : writeSpiFIFO
  PORT MAP (
    srst => reset_design,
    wr_clk => fifoclk,
    rd_clk => Clk,
    din => fifo_unconned,
    wr_en => fifowren,
    rd_en => fifo_rden,
    dout => fifodout(3 downto 0),
    full => fifo_full,
    empty => fifo_empty,
    prog_full => fifo_almostfull,
    wr_rst_busy => open,
    rd_rst_busy => open 
  );
-----------------------------  pass output signals  --------------------------------------------------
    readdone                <= read_done;
    out_read_inprogress     <= read_inprogress; 
    out_rd_SpiCsB           <= rd_SpiCsB;
    out_SpiCsB_N            <= SpiCsB_N; 
    out_read_start          <= read_start; 
    out_SpiMosi             <= SpiMosi; 
    out_SpiMiso             <= SpiMiso; 
    out_CmdSelect          <= CmdSelect;
    CmdIndex               <= in_CmdIndex;
    out_SpiCsB_FFDin        <= SpiCsB_FFDin; 
    --out_rd_data_valid_cntr <= rd_data_valid_cntr;
    out_rd_data_valid_cntr(2 downto 0) <= er_data_valid_cntr;
    out_rd_data_valid <= rd_data_valid;
    out_rd_rddata <= rd_rddata;
    out_rd_rddata_all <= rd_rddata_all;
    out_cmdreg32 <= cmdreg32;
    out_cmdcntr32 <= rd_cmdcounter32;
    out_nword_cntr <= rd_nword_cntr_dly;

    out_er_status <= er_status;
    out_wrfifo_rden <= fifo_rden;

    out_wr_statusdatavalid <= StatusDataValid;
    out_wr_rddata <= rddata;
    out_wr_spistatus <= spi_status; 
-----------------------------  select command  --------------------------------------------------
  CmdSelect <= CmdStatus when CmdIndex = x"1" else
               CmdRDID   when CmdIndex = x"2" else
               CmdRDFlashPara   when CmdIndex = x"3" else
               CmdRDFR24Quad    when CmdIndex = x"4" else
               x"FF";

-----------------------------  read sectors  --------------------------------------------------
processread : process (Clk)
  begin
  if rising_edge(Clk) then
  case rdstate is 
   when S_RD_IDLE =>
        rd_SpiCsB <= '1';
        if (startaddrvalid = '1') then rd_current_sector_addr <= startaddr; end if;  -- no sync required. lots of time spent in _top
        if (read = '1') then  -- one shot based on I/F erase -> synced_erase input going high e.g. "if rising edge erase"
          rd_data_valid_cntr <= "0000";
          rd_cmdcounter32 <= "100111";  -- 32 bit command (cmd + addr = 40 bits)
          rd_nword_limit(31 downto 0) <= in_wdlimit(31 downto 0); 
          rd_rddata <= x"0000";
          rd_rddata_all <= x"0000";
          --rd_cmdreg32 <=  CmdSelect & X"00000000";  
          --rd_cmdreg32 <=  CmdSelect & AddSelect;  
          --rd_cmdreg32 <=  CmdSelect & in_rdAddr;  
          rd_cmdreg32 <=  CmdWE & X"00000000";  -- Write Enable
          read_inprogress <= '1';
          rdstate <= S_RD_S4BMode_ASSCS1;
          read_done <= '0';
         end if;
                       
-----------------   Set 4 Byte mode first -----------------------------------------------------
   when S_RD_S4BMode_ASSCS1=>
        rd_nword_limit <= rd_nword_limit + 1; --we're given nwords-1
        rd_SpiCsB <= '0';
        rdstate <= S_RD_S4BMode_WRCMD;
          
   when S_RD_S4BMode_WRCMD =>    -- Set WE bit
        if (rd_cmdcounter32 /= 32) then rd_cmdcounter32 <= rd_cmdcounter32 - 1; 
          rd_cmdreg32 <= rd_cmdreg32(38 downto 0) & '0'; 
        else
          rd_cmdreg32 <=  Cmd4BMode  & X"00000000";  -- Flag Status registrd
          rd_cmdcounter32 <= "100111";  -- 40 bit command+addr
          rd_SpiCsB <= '1';   -- turn off SPI 
          rdstate <= S_RD_S4BMode_ASSCS2; 
        end if;
        
   when S_RD_S4BMode_ASSCS2 =>
        rd_SpiCsB <= '0';
        rdstate <= S_RD_S4BMode_WR4BADDR;
                        
   when S_RD_S4BMode_WR4BADDR =>    -- Set 4-Byte address Mode
        if (rd_cmdcounter32 /= 32) then rd_cmdcounter32 <= rd_cmdcounter32 - 1;  
           rd_cmdreg32 <= rd_cmdreg32(38 downto 0) & '0';
        else 
          rd_SpiCsB <= '1';   -- turn off SPI
          --rd_cmdcounter32 <= "100111";  -- 32 bit command
          --rd_cmdcounter32 <= "110001";  -- 32 bit address + 8 bit command + 5 bit wait
          rd_cmdcounter32 <= "110000";  -- 32 bit address + 8 bit command + 5 bit wait
          --rd_cmdreg32 <=  CmdSelect & in_rdAddr;
          rd_cmdreg32 <=  CmdSelect & rd_current_sector_addr;  
          rdstate <= S_RD_CS1;  
        end if;  
-------------------------  end set 4 byte Mode

   when S_RD_CS1 =>
        rd_SpiCsB <= '0';
        rdstate <= S_RD_RDCMD;

   when S_RD_RDCMD =>     -- read register according to selected command 
        if (rd_cmdcounter32 /= 0) then rd_cmdcounter32 <= rd_cmdcounter32 - 1; -- set to 7: 39 - 8 - 24 (8 bits command, 24 bits addr in 3 bytes mode)
           rd_cmdreg32 <= rd_cmdreg32(38 downto 0) & '0';

           rd_rddata_all <= rd_rddata_all(14 downto 0) & SpiMiso;  -- deser 1:8 
        --if (rd_cmdcounter32 >= 7) then rd_cmdcounter32 <= rd_cmdcounter32 - 1; -- set to 7: 39 - 8 - 24 (8 bits command, 24 bits addr in 3 bytes mode)
        else
          rd_data_valid_cntr <= rd_data_valid_cntr + 1;
          rd_rddata <= rd_rddata(14 downto 0) & SpiMiso;  -- deser 1:8 
          --rd_rddata <= rd_rddata(46 downto 0) & SpiMiso;  -- deser 1:8 
          --rd_rddata <= rd_rddata(6 downto 0) & "0";  -- deser 1:8 
          --if (rd_data_valid_cntr = 47) then  -- Check Status after 8 bits (+1) of status read
          --if (rd_data_valid_cntr = 14) then
          if (rd_data_valid_cntr = 15) then
              rd_data_valid <= '1';
              rd_nword_cntr <= rd_nword_cntr + 1;
              rd_nword_cntr_dly <= rd_nword_cntr;
          else
              rd_data_valid <= '0';
          end if;
          -- this is hardcoded, only able to read one page for now
          if (rd_nword_cntr = rd_nword_limit) then  -- Check Status after 8 bits (+1) of status read
          --if (rd_nbyte_cntr = x"c") then  -- Check Status after 8 bits (+1) of status read
          --if (rd_nbyte_cntr = in_rdAddr) then  -- Check Status after 8 bits (+1) of status read
            rdstate <= S_RD_EXIT4BMode_ASSCS1;   -- Done. All info read 
            rd_nword_cntr <= x"00000000";
            rd_data_valid_cntr <= "0000";
            rd_cmdcounter32 <= "100111";
            rd_cmdreg32 <= CmdExit4BMode & X"00000000";
            rd_SpiCsB <= '1';
          end if;  -- if rddata valid
        end if; -- cmdcounter /= 32

    when S_RD_EXIT4BMode_ASSCS1 =>
        rd_SpiCsB <= '0';   
        rdstate <= S_RD_EXIT4BMODE;

    when S_RD_EXIT4BMODE =>    -- Back to 3 Byte Mode
        if (rd_cmdcounter32 /= 32) then rd_cmdcounter32 <= rd_cmdcounter32 - 1;  
          rd_cmdreg32 <= rd_cmdreg32(38 downto 0) & '0';
        else 
          rd_SpiCsB <= '1';   -- turn off SPI 
          read_inprogress <= '0';
          read_done <= '1';
          rdstate <= S_RD_IDLE;  
        end if; 
   end case;  
 end if;  -- Clk
end process processread;
-----------------------------  read sectors end  --------------------------------------------------

-----------------------------  erase sectors  --------------------------------------------------
processerase : process (Clk)
  begin
  if rising_edge(Clk) then
  case erstate is 
   when S_ER_IDLE =>
        er_SpiCsB <= '1';
        --if (sectorcountvalid = '1') then er_sector_count <= sectorcount; end if;  -- no sync required
        if (startaddrvalid = '1') then er_current_sector_addr <= startaddr; end if;  -- no sync required. lots of time spent in _top
        if (erase_start = '1') then  -- one shot based on I/F erase -> synced_erase input going high e.g. "if rising edge erase"
          er_data_valid_cntr <= "000";
          er_cmdcounter32 <= "100111";  -- 32 bit command (cmd + addr = 40 bits)
          er_rddata <= "00";
          er_cmdreg32 <=  CmdWE & X"00000000";  -- Write Enable
          erase_inprogress <= '1';
          erase_done <= '0';
          erstate <= S_S4BMode_ASSCS1;
         end if;
                       
-----------------   Set 4 Byte mode first -----------------------------------------------------
   when S_S4BMode_ASSCS1 =>
        er_SpiCsB <= '0';
        erstate <= S_S4BMode_WRCMD;
          
   when S_S4BMode_WRCMD =>    -- Set WE bit
        if (er_cmdcounter32 /= 32) then er_cmdcounter32 <= er_cmdcounter32 - 1; 
          er_cmdreg32 <= er_cmdreg32(38 downto 0) & '0'; 
        else
          er_cmdreg32 <=  Cmd4BMode  & X"00000000";  -- Flag Status register
          er_cmdcounter32 <= "100111";  -- 40 bit command+addr
          er_SpiCsB <= '1';   -- turn off SPI 
          erstate <= S_S4BMode_ASSCS2; 
        end if;
        
   when S_S4BMode_ASSCS2 =>
        er_SpiCsB <= '0';
        erstate <= S_S4BMode_WR4BADDR;
                        
   when S_S4BMode_WR4BADDR =>    -- Set 4-Byte address Mode
        if (er_cmdcounter32 /= 32) then er_cmdcounter32 <= er_cmdcounter32 - 1;  
           er_cmdreg32 <= er_cmdreg32(38 downto 0) & '0';
        else 
          er_SpiCsB <= '1';   -- turn off SPI
          er_cmdcounter32 <= "100111";  -- 32 bit command
          er_cmdreg32 <=  CmdWE & X"00000000";  -- Write Enable 
          erstate <= S_ER_ASSCS1;  
        end if;  
-------------------------  end set 4 byte Mode

   when S_ER_ASSCS1 =>
        erstate <= S_ER_WRCMD;
        er_SpiCsB <= '0';
        er_status <= "11";
                  
   when S_ER_WRCMD =>    -- Set WE bit
         if (er_cmdcounter32 /= 32) then er_cmdcounter32 <= er_cmdcounter32 - 1;  
           er_cmdreg32 <= er_cmdreg32(38 downto 0) & '0';
         else 
           er_SpiCsB <= '1';   -- turn off SPI
           er_cmdreg32 <=  CmdSE24 & er_current_sector_addr;  -- 4-Byte Sector erase 
           --er_cmdreg32 <=  CmdSSE32 & er_current_sector_addr;  -- 4-Byte Sector erase 
           er_cmdcounter32 <= "100111";
           erstate <= S_ER_ASSCS2;        
         end if;
                   
   when S_ER_ASSCS2 =>
        er_SpiCsB <= '0';   
        erstate <= S_ER_ERASECMD;
                      
   when S_ER_ERASECMD =>     -- send erase command
        er_cmdreg32 <= er_cmdreg32(38 downto 0) & '0';
        if (er_cmdcounter32 /= 0) then er_cmdcounter32 <= er_cmdcounter32 - 1; -- send erase + 24 bit address???? 
                                                                               -- this comment from example design is wrong, should be erase + 32 bit address, here 4 byte address mode is on
        else
          er_SpiCsB <= '1';   -- turn off SPI
          er_cmdcounter32 <= "100111";
          --er_cmdreg32 <=  CmdFLAGStatus & X"00000000";  -- Read Status register
          er_cmdreg32 <=  CmdStatus & X"00000000";  -- Read Status register
          erstate <= S_ER_ASSCS3;
        end if;
                                      
   when S_ER_ASSCS3 =>
        er_SpiCsB <= '0';   
        erstate <= S_ER_RDSTAT;
                  
   when S_ER_RDSTAT =>     -- read status register....X03 = Program/erase in progress 
        if (er_cmdcounter32 >= 31) then er_cmdcounter32 <= er_cmdcounter32 - 1;
            er_cmdreg32 <= er_cmdreg32(38 downto 0) & '0';
        else
          er_data_valid_cntr <= er_data_valid_cntr + 1;
          er_rddata <= er_rddata(1) & SpiMiso;  -- deser 1:8 
          --er_rddata <= er_rddata(1) & "0";  -- deser 1:8 
          if (er_data_valid_cntr = 7) then  -- Check Status after 8 bits (+1) of status read
            er_status <= er_rddata;   -- Check WE and ERASE in progress one cycle after er_rddate
            if (er_status = 0 or in_simulation) then
              if (er_sector_count = 0) then 
                erstate <= S_ER_IDLE;   -- Done. All sectors erased
                erase_inprogress <= '0';
                erase_done <= '1';
              else 
                er_current_sector_addr <= er_current_sector_addr + SubSectorSize;
                er_sector_count <= er_sector_count - 1;
                er_cmdreg32 <=  CmdWE & X"00000000";   
                er_cmdcounter32 <= "100111";
                er_SpiCsB <= '1';
                erstate <= S_ER_ASSCS1;
              end if;
            end if; -- if status
          end if;  -- if rddata valid
        end if; -- cmdcounter /= 32
   end case;  
 end if;  -- Clk
end process processerase;

-----------------------------  erase sectors end  --------------------------------------------------

------------------------------------  Write Data to Program Pages  ----------------------              
processProgram  : process (Clk)
  begin
  if rising_edge(Clk) then
  case wrstate is 
   when S_WR_IDLE =>
        SpiCsB <= '1';
        write_done <= '0';
        if (startaddrvalid = '1') then Current_Addr <= startaddr; end if;  -- no sync required. lots of time spent in _top
        if (pagecountvalid = '1') then page_count <= pagecount; end if;  -- no sync required
        --if (synced_fifo_almostfull(1) = '1') then         -- some  starting point     
        if (write = '1') then         -- some  starting point           
          dopin_ts <= "1110";
          data_valid_cntr <= "000";
          cmdcounter32 <= "100111";  -- 32 bit command
          rddata <= "00";
          cmdreg32 <=  CmdWE & X"00000000";  -- Set WE bit
          fifo_rden <= '0';
          wrdata_count <= "000";
          write_nwords_limit <= write_nwords & "00";
          spi_wrdata <= X"00000000";
          wrstate <= S_WR_S4BMode_ASSCS1;
          --wrstate <= S_WR_ASSCS1;
        end if;
                       
-----------------   Set 4 Byte mode first -----------------------------------------------------
   when S_WR_S4BMode_ASSCS1 =>
        SpiCsB <= '0';
        wrstate <= S_WR_S4BMode_WRCMD;
          
   when S_WR_S4BMode_WRCMD =>    -- Set WE bit
        if (cmdcounter32 /= 32) then cmdcounter32 <= cmdcounter32 - 1; 
          cmdreg32 <= cmdreg32(38 downto 0) & '0'; 
        else
          cmdreg32 <=  Cmd4BMode  & X"00000000";  -- Flag Status register
          cmdcounter32 <= "100111";  -- 40 bit command+addr
          SpiCsB <= '1';   -- turn off SPI 
          wrstate <= S_WR_S4BMode_ASSCS2; 
        end if;
        
   when S_WR_S4BMode_ASSCS2 =>
        SpiCsB <= '0';
        wrstate <= S_WR_S4BMode_WR4BADDR;
                        
   when S_WR_S4BMode_WR4BADDR =>    -- Set 4-Byte address Mode
        if (cmdcounter32 /= 32) then cmdcounter32 <= cmdcounter32 - 1;  
           cmdreg32 <= cmdreg32(38 downto 0) & '0';
        else 
          SpiCsB <= '1';   -- turn off SPI
          cmdcounter32 <= "100111";  -- 32 bit command
          cmdreg32 <=  CmdWE & X"00000000";  -- Write Enable 
          wrstate <= S_WR_ASSCS1;  
        end if;  
-------------------------  end set 4 byte Mode

   when S_WR_ASSCS1 =>
        --if (page_count /= 0) then 
        --  if (synced_fifo_almostfull(1) = '1') then
        --    SpiCsB <= '0';
        --    wrstate <= S_WR_WRCMD;
        --  end if;
        --else 
        --don't wait for fifo anymore?
          SpiCsB <= '0';
          wrstate <= S_WR_WRCMD;
        --end if;
                  
   when S_WR_WRCMD =>    -- Set WE bit
        if (cmdcounter32 /= 32) then cmdcounter32 <= cmdcounter32 - 1;  
          cmdreg32 <= cmdreg32(38 downto 0) & '0';
        elsif (write_nwords_limit /= 0) then    -- Next PP
          SpiCsB <= '1';   -- turn off SPI
          cmdreg32 <=  CmdPP32Quad & Current_Addr;  -- Program Page at Current_Addr
          --cmdreg32 <=  CmdPP24Quad & Current_Addr;  -- Program Page at Current_Addr
          cmdcounter32 <= "100111";
          wrstate <= S_WR_ASSCS2;
        else                              -- Done with writing Program Pages. Turn off 4 byte Mode
          cmdcounter32 <= "100111";
          cmdreg32 <= CmdExit4BMode & X"00000000";
          SpiCsB <= '1';
          write_done <= '1';
          --wrstate <= S_WR_IDLE;  
          wrstate <= S_EXIT4BMode_ASSCS1;        
        end if;
                   
   when S_WR_ASSCS2 =>
        SpiCsB <= '0';
        wrstate <= S_WR_PROGRAM;
                                                 
   when S_WR_PROGRAM =>  -- send Program command
        if (cmdcounter32 /= 0) then cmdcounter32 <= cmdcounter32 - 1;
          cmdreg32 <= cmdreg32(38 downto 0) & '0';
        else 
          fifo_rden <= '1';
          wrstate <= S_WR_DATA;
          dopin_ts <= "0000";
        end if;
                          
   when S_WR_DATA =>
        SpiCsB <= '0';
        wrdata_count <= wrdata_count +1;
        if (wrdata_count = 7) then -- 8x4 bits from FIFO.  wrdata_count rolls over to 0
          Current_Addr <= Current_Addr + 4;  -- 4 bytes out of 256 bytes per page   
          if (write_nwords_limit /= 0) then
            write_nwords_limit <= write_nwords_limit - 1;
          end if;
          if ((Current_Addr(7 downto 0) = 252)) then   -- every 256 bytes (1 PP) written, only check lower bits = mod 256
            SpiCsB <= '1';
            fifo_rden <= '0';
            dopin_ts <= "1110";
            cmdreg32 <=  CmdStatus & X"00000000";  -- Read Status register next
            --cmdreg32 <=  CmdFLAGStatus & X"00000000";  -- Read Status register next
            wrstate <= S_WR_PPDONEPRE;  -- one PP done
          end if;
        end if;
--                    
-- this part is strange, if only do read stataus once, will get 11111111 always from miso
   when S_WR_PPDONEPRE =>
        SpiCsB <= '0';
        cmdcounter32 <= "100111";
        wrstate <= S_WR_PPDONESTATUS;
                       
   when S_WR_PPDONESTATUS =>    
        if (cmdcounter32 /= 32) then cmdcounter32 <= cmdcounter32 - 1; 
          cmdreg32 <= cmdreg32(38 downto 0) & '0'; 
        else
          cmdreg32 <=  CmdStatus  & X"00000000";  
          cmdcounter32 <= "100111";  
          SpiCsB <= '1';   -- turn off SPI 
          wrstate <= S_WR_PPDONE; 
        end if;

   when S_WR_PPDONE =>
        dopin_ts <= "1110";
        SpiCsB <= '0';
        data_valid_cntr <= "000";
        cmdcounter32 <= "100111";
        wrstate <= S_WR_PPDONE_WAIT;
--                    
   when S_WR_PPDONE_WAIT => 
        fifo_rden <= '0';  
        if (reset_design = '1') then wrstate <= S_WR_IDLE;
        else 
          if (cmdcounter32 /= 31) then cmdcounter32 <= cmdcounter32 - 1; 
            cmdreg32 <= cmdreg32(38 downto 0) & '0';
          else -- keep reading the status register
            data_valid_cntr <= data_valid_cntr + 1;  -- rolls over to 0
            rddata <= rddata(1) & SpiMiso;  -- deser 1:8  
            --rddata <= rddata(1) & "0" ;  -- deser 1:8  
            if (data_valid_cntr = 7) then  -- catch status byte
              StatusDataValid <= '1';    -- copy WE and Write in progress one cycle after rddate
            else 
              StatusDataValid <= '0';
            end if;
            if (StatusDataValid = '1') then spi_status <= rddata; end if;  --  rddata valid from previous cycle
            if (spi_status = 0 or in_simulation) then    -- Done with page program
            --if spi_status = 1 then    -- Done with page program
              SpiCsB <= '1';   -- turn off SPI
              cmdcounter32 <= "100111";
              cmdreg32 <=  CmdWE & X"00000000";  -- Set WE bit
              data_valid_cntr <= "000";
              StatusDataValid <= '0';
              spi_status <= "11";
              page_count <= page_count - 1;
              wrstate <= S_WR_ASSCS1;
            end if;  -- spi_status
          end if;  -- cmdcounter32
        end if;  -- reset_design
                          
-----------------   Exit 4 Byte mode ------------------------------------    
   when S_EXIT4BMode_ASSCS1 =>
        SpiCsB <= '0';   
        wrstate <= S_EXIT4BMODE;
         
   when S_EXIT4BMODE =>    -- Back to 3 Byte Mode
        if (cmdcounter32 /= 32) then cmdcounter32 <= cmdcounter32 - 1;  
          cmdreg32 <= cmdreg32(38 downto 0) & '0';
        else 
          SpiCsB <= '1';   -- turn off SPI 
          write_done <= '1';
          wrstate <= S_WR_IDLE;  
        end if; 
    end case;
   end if;  -- Clk
end process processProgram;

-----------------------------  write sectors end  --------------------------------------------------
MuxMosi_int: process(wrstate)   -- 1 bit command/data or 4 bit data to SPI
 begin
   case wrstate is
        when S_WR_DATA =>
          SpiMosi_int <= fifodout(0);
        when others =>
          SpiMosi_int <= cmdreg32(39);
   end case;

end process MuxMosi_int;

MuxMosi: process(CLK)   -- 1 bit command/data or 4 bit data to SPI  POR_reg
 begin
     if (read_inprogress = '1') then SpiMosi <= rd_cmdreg32(39);
     elsif (erase_inprogress = '1') then SpiMosi <= er_cmdreg32(39);
     else SpiMosi <= SpiMosi_int;
     end if;
end process MuxMosi;

MuxCsB: process (Clk)
 begin
     if (read_inprogress = '1') then SpiCsB_FFDin <= rd_SpiCsB;
     elsif (erase_inprogress = '1') then SpiCsB_FFDin <= er_SpiCsB;
     else SpiCsB_FFDin <= SpiCsB;
     end if;
end process MuxCsB;

process (clk)  -- Syncers
  begin
    if rising_edge(clk) then  
          synced_fifo_almostfull <= synced_fifo_almostfull(0) & fifo_almostfull;  -- sync FIFO almostfull
          synced_erase <= synced_erase(0) & erase;
          synced_read <= synced_read(0) & read;
    end if;
end process;

--------------********* misc **************---------------------
reset_design <= reset;
fifo_unconned(15 downto 0) <= data_to_fifo;

-- to top design. Some may require syncronizers when used   
fifofull    <= fifo_full;
fifoempty   <= fifo_empty;        -- May require synconizer when used
fifoafull   <= fifo_almostfull;   -- May require synconizer when used
fifowrerr   <= wrerr;
fiforderr   <= rderr;             -- May require synconizer when used
eraseing    <= erase_inprogress;
erasedone    <= erase_done;
writedone   <= write_done;        -- Done with writing to SPI

end behavioral;

--------------------------------------   Neg edge Flop ------------------------
library ieee;
use ieee.std_logic_1164.all;
   
entity SpiCsBflop is  
   port(C, D  : in std_logic; 
        Q     : out std_logic);  
end SpiCsBflop;  

architecture flop of SpiCsBflop is  -- neg edge flop
   begin  
     process (C)  
     begin  
       if falling_edge(C) then         
          Q <= D;  
       end if;  
     end process;  
end flop;
