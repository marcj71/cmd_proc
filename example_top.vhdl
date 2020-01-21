-- Example for cmd_proc: the simple command processor
-- Copyright 2019, 2020 Marc Joosen

-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
-- 
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
-- 
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity example_top is
	port (
		clk:		in std_logic;

		cmd_txd:	out std_logic;
		cmd_rxd:	in std_logic;

		output:		out std_logic_vector(7 downto 0)
	);
end;

 
architecture rtl of example_top is
	signal logic_0:		std_logic := '0';

	signal reset:		std_logic := '0';
	signal temp:		std_logic_vector(31 downto 0) := (others => '0');
	signal count:		unsigned(31 downto 0) := (others => '0');
	signal out_i:		std_logic_vector(7 downto 0) := (others => '0');

	-- UART interface
	signal tx_data:		std_logic_vector(7 downto 0);
	signal tx_req:		std_logic := '0';
	signal tx_brk:		std_logic := '0';
	signal tx_busy:		std_logic;
	signal rx_data:		std_logic_vector(7 downto 0);
	signal rx_data_valid:	std_logic := '0';
	signal rx_brk:		std_logic;
	signal rx_err:		std_logic;

	-- command processor
	signal cmd_proc_reset:	std_logic;
	signal rd_data:		std_logic_vector(31 downto 0);
	signal wr_data:		std_logic_vector(31 downto 0);
	signal address:		std_logic_vector(15 downto 0);
--	signal read_req: 	std_logic;
	signal write_req:	std_logic;
begin

	logic_0 <= '0';
	reset   <= '0';

	-- register interface -------------------------------------------------

	read_multiplexer: process(all)
	begin
		rd_data <= (others => '0');
		case address is
		when x"0000" =>
			rd_data <= x"01020304";		-- version
		when x"0001" =>
			rd_data(7 downto 0) <= out_i;	-- debug pins
		when x"0002" =>
			rd_data <= temp;		-- test
		when x"0100" =>
			rd_data <= std_logic_vector(count);	-- clock cycle counter

		when others =>
			rd_data <= (others => '0');

		end case;
	end process;

	-- infer all registers here
	write_decoder: process(clk)
	begin
		if rising_edge(clk) then
			if reset = '1' then
				output <= (others => '0');

			else
				if write_req = '1' then
					case address is
					when x"0001" =>
						out_i <= wr_data(7 downto 0);
					when x"0002" =>
						temp  <= wr_data;

					when others =>
						null;

					end case;
				end if;
			end if;
		end if;
	end process;


	-- counter ------------------------------------------------------------

	counter: process(clk)
	begin
		if rising_edge(clk) then
			if reset = '1' then
				count <= (others => '0');
			else
				count <= count + 1;
			end if;
		end if;
	end process;

	output <= out_i;


	-- command interface --------------------------------------------------

	cmd_uart: entity work.fluart
		generic map(
			CLK_FREQ => 50_000_000,	-- main frequency (Hz)
			SER_FREQ => 115200,	-- bit rate (bps)
			BRK_LEN  => 10
		)
		port map (
			clk	=> clk,
			reset	=> reset,

			txd	=> cmd_txd,
			rxd	=> cmd_rxd,

			tx_data		=> tx_data,
			tx_req		=> tx_req,
			tx_brk		=> logic_0,
			tx_busy		=> tx_busy,
			tx_end		=> open,
			rx_data		=> rx_data,
			rx_data_valid	=> rx_data_valid,
			rx_brk		=> rx_brk,
			rx_err		=> rx_err
		);

	cmd_proc_reset <= reset or rx_brk or rx_err;

	cmd_proc: entity work.cmd_proc
		generic map (
			ADDR_SIZE	=> 16,
			DATA_SIZE	=> 32
		)
		port map (
			clk		=> clk,
			reset		=> cmd_proc_reset,

			-- UART interface
			rx_data		=> rx_data,
			rx_data_valid	=> rx_data_valid,

			tx_data		=> tx_data,
			tx_req		=> tx_req,
			tx_busy		=> tx_busy,

			-- user logic interface
			address 	=> address,
			rd_data		=> rd_data,
			wr_data		=> wr_data,
			read_req	=> open,
			write_req	=> write_req
		);

end architecture;
