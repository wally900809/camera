-------------------------------------------------------------------------
-- Company     : Yansar
-- Engineer    : Golovachenko Victor
--
-- Create Date : 19.06.2014 11:14:45
-- Module Name : ccd_spi
--
-- ����������/�������� :
--
--
-- Revision:
-- Revision 0.01 - File Created
--
-------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.ccd_pkg.all;
use work.spi_pkg.all;
use work.vicg_common_pkg.all;
use work.reduce_pack.all;

entity ccd_spi is
generic(
G_SPI_WRITE : std_logic := '1';
G_SIM : string := "OFF"
);
port(
p_out_physpi    : out  TSPI_pinout;
p_in_physpi     : in   TSPI_pinin;
--p_out_ccdrst_n  : out  std_logic;

--p_in_fifo_dout  : in   std_logic_vector(15 downto 0);
--p_out_fifo_rd   : out  std_logic;
--p_in_fifo_empty : in   std_logic;

p_in_deser_rdy  : in   std_logic;
p_in_align      : in   std_logic;
p_out_init_done : out  std_logic;
p_out_err       : out  std_logic;

p_out_tst       : out  std_logic_vector(31 downto 0);
p_in_tst        : in   std_logic_vector(31 downto 0);

p_in_clk        : in   std_logic;
p_in_rst        : in   std_logic
);
end;

architecture behavior of ccd_spi is

constant CI_SPI_WRITE : std_logic := G_SPI_WRITE;
constant CI_SPI_READ : std_logic := not G_SPI_WRITE;

component spi_core is
generic(
G_DBG : string := "OFF";
G_AWIDTH : integer := 16;
G_DWIDTH : integer := 16
);
port(
p_in_adr    : in   std_logic_vector(G_AWIDTH - 1 downto 0);
p_in_data   : in   std_logic_vector(G_DWIDTH - 1 downto 0); --FPGA -> DEV
p_out_data  : out  std_logic_vector(G_DWIDTH - 1 downto 0); --FPGA <- DEV
p_in_dir    : in   std_logic;
p_in_start  : in   std_logic;

p_out_busy  : out  std_logic;

p_out_physpi : out TSPI_pinout;
p_in_physpi  : in  TSPI_pinin;

p_out_tst    : out std_logic_vector(31 downto 0);
p_in_tst     : in  std_logic_vector(31 downto 0);

p_in_clk_en : in   std_logic;
p_in_clk    : in   std_logic;
p_in_rst    : in   std_logic
);
end component;

type TFsm_spireg is (
S_IDLE,

S_RD_CHIPID,
S_RD_CHIPID_1,
S_RD_CHIPID_2,

S_INIT_WR,
S_INIT_WR_1,
S_INIT_WR_2,

S_INIT_RD,
S_INIT_RD_1,
S_INIT_RD_2,

S_WAIT2_BTN,
S_WAIT2_BTN_1,
S_WAIT2_BTN_2,

S_SET_RIO,
S_SET_RIO_1,
S_SET_RIO_2,

S_SET_EXPOSURE,
S_SET_EXPOSURE_1,
S_SET_EXPOSURE_2,

--S_SET_STOP,
--S_SET_STOP_1,
--S_SET_STOP_2,

S_ERR,

S_START_ALIGN,
S_WAIT_ALIGN
);

signal i_fsm_spi_cs     : TFsm_spireg;

signal i_clkcnt         : unsigned(5 downto 0) := (others => '0');
signal i_clk_en         : std_logic := '0';

signal i_busy           : std_logic := '0';
signal i_spi_core_dir   : std_logic := '0';
signal i_spi_core_start : std_logic := '0';
signal i_adr            : std_logic_vector(C_CCD_SPI_AWIDTH - 1 downto 0) := (others => '0');
signal i_txd            : std_logic_vector(C_CCD_SPI_DWIDTH - 1 downto 0) := (others => '0');
signal i_rxd            : std_logic_vector(C_CCD_SPI_DWIDTH - 1 downto 0) := (others => '0');

signal i_regcnt         : unsigned(log2(C_CCD_REGINIT2'length) - 1 downto 0) := (others => '0');

--signal i_ccd_rst_n      : std_logic := '1';
signal i_init_done      : std_logic := '0';
signal i_err            : std_logic := '0';
signal i_align          : std_logic := '0';
signal i_align_start    : std_logic := '0';
signal i_deser_rdy      : std_logic := '0';

signal sr_btn_push      : unsigned(0 to 1) := (others => '0');
signal i_btn_push       : std_logic := '0';
signal tst_fsmstate,tst_fsmstate_dly : std_logic_vector(3 downto 0) := (others => '0');
signal i_spi_core_tst_out : std_logic_vector(31 downto 0) := (others => '0');

signal i_ccd_readout    : std_logic;

signal i_ccd_start      : std_logic;



--MAIN
begin

p_out_tst(0) <= i_clkcnt(i_clkcnt'high);
p_out_tst(1) <= OR_reduce(tst_fsmstate_dly) or i_align or i_ccd_start;
p_out_tst(2) <= i_spi_core_tst_out(1);
p_out_tst(3) <= OR_reduce(i_rxd);
p_out_tst(4) <= p_in_tst(0);
p_out_tst(5) <= i_align_start;
p_out_tst(31 downto 6) <= (others => '0');

--p_out_ccdrst_n <= i_ccd_rst_n;

p_out_init_done <= i_init_done;
p_out_err       <= i_err;

process(p_in_clk)
begin
  if rising_edge(p_in_clk) then
    i_clkcnt <= i_clkcnt + 1;

    if i_clkcnt = (i_clkcnt'range => '1') then
      i_clk_en <= '1';
    else
      i_clk_en <= '0';
    end if;
  end if;
end process;


process(p_in_clk)
begin
  if rising_edge(p_in_clk) then
    if p_in_rst = '1' then
      i_regcnt <= (others => '0');
      i_adr <= (others => '0'); --i_ccd_rst_n <= '1';
      i_txd <= (others => '0');
      i_spi_core_dir <= '0';
      i_spi_core_start <= '0';
      i_init_done <= '0';
      i_err <= '0';
      i_fsm_spi_cs <= S_IDLE; i_ccd_readout <= '1'; i_ccd_start <= '0';
      i_align_start <= '0';

    else
      if i_clk_en = '1' then

        case i_fsm_spi_cs is

          when S_IDLE =>

            if i_btn_push = '1' then
              i_regcnt <= (others => '0'); --i_ccd_rst_n <= '1';
              i_fsm_spi_cs <= S_RD_CHIPID;
            end if;

          --------------------------------
          --
          --------------------------------
          when S_RD_CHIPID =>

            i_adr <= std_logic_vector(TO_UNSIGNED(16#00#, i_adr'length - 1)) & CI_SPI_READ;
            i_spi_core_dir <= C_SPI_READ;
            i_spi_core_start <= '1';
            i_fsm_spi_cs <= S_RD_CHIPID_1;

          when S_RD_CHIPID_1 =>

            i_spi_core_start <= '0';
            i_fsm_spi_cs <= S_RD_CHIPID_2;

          when S_RD_CHIPID_2 =>

            if i_busy = '0' then
              if i_rxd /= std_logic_vector(TO_UNSIGNED(16#56FA#, i_rxd'length)) then
                i_fsm_spi_cs <= S_ERR;
              else
                i_fsm_spi_cs <= S_INIT_WR;
              end if;
            end if;


          --------------------------------
          --CCD INIT (Enable clock management)
          --------------------------------
          when S_INIT_WR =>

            for i in 0 to C_CCD_REGINIT'length - 1 loop
              if i_regcnt = i then
                i_adr <= C_CCD_REGINIT(i)(24 downto 16) & CI_SPI_WRITE;
                i_txd <= C_CCD_REGINIT(i)(15 downto 0);
              end if;
            end loop;

            i_spi_core_dir <= C_SPI_WRITE;
            i_spi_core_start <= '1';
            i_fsm_spi_cs <= S_INIT_WR_1;

          when S_INIT_WR_1 =>

            i_spi_core_start <= '0';
            i_fsm_spi_cs <= S_INIT_WR_2;

          when S_INIT_WR_2 =>

            if i_busy = '0' then
              i_fsm_spi_cs <= S_INIT_RD;
            end if;

          --Check it
          when S_INIT_RD =>

            for i in 0 to C_CCD_REGINIT'length - 1 loop
              if i_regcnt = i then
                i_adr <= C_CCD_REGINIT(i)(24 downto 16) & CI_SPI_READ;
                i_txd <= C_CCD_REGINIT(i)(15 downto 0);
              end if;
            end loop;

            i_spi_core_dir <= C_SPI_READ;
            i_spi_core_start <= '1';
            i_fsm_spi_cs <= S_INIT_RD_1;

          when S_INIT_RD_1 =>

            i_spi_core_start <= '0';
            i_fsm_spi_cs <= S_INIT_RD_2;

          when S_INIT_RD_2 =>

            if i_busy = '0' then
              if i_regcnt = TO_UNSIGNED(C_CCD_REGINIT'length - 1, i_regcnt'length) then
                i_regcnt <= (others => '0');
                i_init_done <= '1';
                i_fsm_spi_cs <= S_START_ALIGN;

              else
                if i_rxd /= i_txd then
                  i_fsm_spi_cs <= S_ERR;
                else
                  i_fsm_spi_cs <= S_INIT_WR;
                end if;

                i_regcnt <= i_regcnt + 1;

              end if;
            end if;

          --------------------------------
          --
          --------------------------------
          when S_ERR =>

            i_err <= '1';
            i_fsm_spi_cs <= S_ERR;

          --------------------------------
          --CCD User Reg Control
          --------------------------------
          when S_START_ALIGN =>

            if i_deser_rdy = '1' then
            i_align_start <= '1';
            i_fsm_spi_cs <= S_WAIT_ALIGN;
            end if;

          when S_WAIT_ALIGN =>

            i_align_start <= '0';
            i_spi_core_dir <= C_SPI_WRITE;
            i_spi_core_start <= '0';

            if i_align = '1' then
--            if i_btn_push = '1' then
              i_fsm_spi_cs <= S_SET_RIO;--S_SET_STOP;--S_WAIT_ALIGN;--
            end if;

----          --------------------------------
----          --
----          --------------------------------
----          when S_SET_STOP =>
----
----            if i_btn_push = '1' then
----              i_adr <= std_logic_vector(TO_UNSIGNED(10#192#, C_CCD_SPI_AWIDTH - 1)) & CI_SPI_WRITE;
----              i_txd <= std_logic_vector(TO_UNSIGNED(16#0000#, C_CCD_SPI_DWIDTH));
----
----              i_spi_core_dir <= C_SPI_WRITE;
----              i_spi_core_start <= '1';
----              i_fsm_spi_cs <= S_SET_STOP_1;
----            end if;
----
----          when S_SET_STOP_1 =>
----
----            i_spi_core_start <= '0';
----            i_fsm_spi_cs <= S_SET_STOP_2;
----
----          when S_SET_STOP_2 =>
----
----            if i_busy = '0' then
----              i_fsm_spi_cs <= S_SET_RIO;
----            end if;

          --------------------------------
          --
          --------------------------------
          when S_SET_RIO =>

--          if i_btn_push = '1' then
            for i in 0 to C_CCD_WININIT'length - 1 loop
              if i_regcnt = i then
                i_adr <= C_CCD_WININIT(i)(24 downto 16) & CI_SPI_WRITE;
                i_txd <= C_CCD_WININIT(i)(15 downto 0);
              end if;
            end loop;

            i_spi_core_dir <= C_SPI_WRITE;
            i_spi_core_start <= '1';
            i_fsm_spi_cs <= S_SET_RIO_1;
--          end if;

          when S_SET_RIO_1 =>

            i_spi_core_start <= '0';
            i_fsm_spi_cs <= S_SET_RIO_2;

          when S_SET_RIO_2 =>

            if i_busy = '0' then
              if i_regcnt = TO_UNSIGNED(C_CCD_WININIT'length - 1, i_regcnt'length) then
                i_regcnt <= (others => '0');
                i_fsm_spi_cs <= S_SET_EXPOSURE;

              else
                i_fsm_spi_cs <= S_SET_RIO;
                i_regcnt <= i_regcnt + 1;

              end if;
            end if;

          --------------------------------
          --
          --------------------------------
          when S_SET_EXPOSURE =>

            for i in 0 to C_CCD_EXPINIT'length - 1 loop
              if i_regcnt = i then
                i_adr <= C_CCD_EXPINIT(i)(24 downto 16) & CI_SPI_WRITE;
                i_txd <= C_CCD_EXPINIT(i)(15 downto 0);
              end if;
            end loop;

            i_spi_core_dir <= C_SPI_WRITE;
            i_spi_core_start <= '1';
            i_fsm_spi_cs <= S_SET_EXPOSURE_1;

          when S_SET_EXPOSURE_1 =>

            i_spi_core_start <= '0';
            i_fsm_spi_cs <= S_SET_EXPOSURE_2;

          when S_SET_EXPOSURE_2 =>

            if i_busy = '0' then
              if i_regcnt = TO_UNSIGNED(C_CCD_EXPINIT'length - 1, i_regcnt'length) then
                i_regcnt <= (others => '0');
                i_fsm_spi_cs <= S_WAIT2_BTN;

              else
                i_fsm_spi_cs <= S_SET_EXPOSURE;
                i_regcnt <= i_regcnt + 1;

              end if;
            end if;

          --------------------------------
          --
          --------------------------------
          when S_WAIT2_BTN =>

--            if i_btn_push = '1' then
              i_adr <= std_logic_vector(TO_UNSIGNED(10#192#, C_CCD_SPI_AWIDTH - 1)) & CI_SPI_WRITE;
              i_txd <= std_logic_vector(TO_UNSIGNED(16#0000#, C_CCD_SPI_DWIDTH - 1)) & i_ccd_readout;

              i_spi_core_dir <= C_SPI_WRITE;
              i_spi_core_start <= '1';
              i_fsm_spi_cs <= S_WAIT2_BTN_1;
--            end if;

          when S_WAIT2_BTN_1 =>

            i_spi_core_start <= '0';
            i_fsm_spi_cs <= S_WAIT2_BTN_2;

          when S_WAIT2_BTN_2 =>

            if i_busy = '0' then
              if i_btn_push = '1' then
              i_ccd_readout <= not i_ccd_readout;
              i_ccd_start <= '1';
              i_fsm_spi_cs <= S_WAIT2_BTN;
              end if;
            end if;

        end case;

      end if; --if i_clk_en = '1' then
    end if;
  end if;
end process;


m_spi_core : spi_core
generic map(
G_DBG => "ON",
G_AWIDTH => C_CCD_SPI_AWIDTH,
G_DWIDTH => C_CCD_SPI_DWIDTH
)
port map(
p_in_adr    => i_adr,
p_in_data   => i_txd,
p_out_data  => i_rxd,
p_in_dir    => i_spi_core_dir,
p_in_start  => i_spi_core_start,

p_out_busy  => i_busy,

p_out_physpi => p_out_physpi,
p_in_physpi  => p_in_physpi,

p_out_tst    => i_spi_core_tst_out,
p_in_tst     => p_in_tst,

p_in_clk_en => i_clk_en,
p_in_clk    => p_in_clk,
p_in_rst    => p_in_rst
);

process(p_in_clk)
begin
  if rising_edge(p_in_clk) then
    i_align <= p_in_align;
    i_deser_rdy <= p_in_deser_rdy;
  end if;
end process;

process(p_in_clk)
begin
  if rising_edge(p_in_clk) then

    if i_clk_en = '1' then
    sr_btn_push <= p_in_tst(0) & sr_btn_push(0 to 0);
    end if;

    i_btn_push <= sr_btn_push(0) and not sr_btn_push(1);

    tst_fsmstate_dly <= tst_fsmstate;
  end if;
end process;


tst_fsmstate <= std_logic_vector(TO_UNSIGNED(16#0B#,tst_fsmstate'length)) when i_fsm_spi_cs = S_WAIT_ALIGN       else
                std_logic_vector(TO_UNSIGNED(16#0A#,tst_fsmstate'length)) when i_fsm_spi_cs = S_ERR           else
                std_logic_vector(TO_UNSIGNED(16#09#,tst_fsmstate'length)) when i_fsm_spi_cs = S_RD_CHIPID     else
                std_logic_vector(TO_UNSIGNED(16#08#,tst_fsmstate'length)) when i_fsm_spi_cs = S_RD_CHIPID_1   else
                std_logic_vector(TO_UNSIGNED(16#07#,tst_fsmstate'length)) when i_fsm_spi_cs = S_RD_CHIPID_2   else
                std_logic_vector(TO_UNSIGNED(16#06#,tst_fsmstate'length)) when i_fsm_spi_cs = S_INIT_WR       else
                std_logic_vector(TO_UNSIGNED(16#05#,tst_fsmstate'length)) when i_fsm_spi_cs = S_INIT_WR_1     else
                std_logic_vector(TO_UNSIGNED(16#04#,tst_fsmstate'length)) when i_fsm_spi_cs = S_INIT_WR_2     else
                std_logic_vector(TO_UNSIGNED(16#03#,tst_fsmstate'length)) when i_fsm_spi_cs = S_INIT_RD       else
                std_logic_vector(TO_UNSIGNED(16#02#,tst_fsmstate'length)) when i_fsm_spi_cs = S_INIT_RD_1     else
                std_logic_vector(TO_UNSIGNED(16#01#,tst_fsmstate'length)) when i_fsm_spi_cs = S_INIT_RD_2     else
                std_logic_vector(TO_UNSIGNED(16#00#,tst_fsmstate'length)); --i_fsm_spi_cs = S_IDLE              else
--                std_logic_vector(TO_UNSIGNED(16#0E#,tst_fsmstate'length)) when i_fsm_spi_cs = S_WAIT2_BTN     else
--                std_logic_vector(TO_UNSIGNED(16#0D#,tst_fsmstate'length)) when i_fsm_spi_cs = S_WAIT1_BTN     else
--                std_logic_vector(TO_UNSIGNED(16#0F#,tst_fsmstate'length)) when i_fsm_spi_cs = S_CCD_RST_1     else
--                std_logic_vector(TO_UNSIGNED(16#0C#,tst_fsmstate'length)) when i_fsm_spi_cs = S_CCD_RST       else


--END MAIN
end architecture;

