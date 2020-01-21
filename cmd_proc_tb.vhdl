-- Testbench for cmd_proc: the simple command processor
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


entity cmd_proc_tb is
end;


architecture testbench of cmd_proc_tb is
	constant ADDR_SIZE: integer := 16;
	constant DATA_SIZE: integer := 16;

	signal clk:		std_logic := '0';
	signal reset:		std_logic := '0';

	-- UART interface
	signal rx_data:		std_logic_vector(7 downto 0) := (others => '0');
	signal rx_data_valid:	std_logic := '0';

	signal tx_data:		std_logic_vector(7 downto 0) := (others => '0');
	signal tx_req:		std_logic := '0';
	signal tx_busy:		std_logic := '0';

	-- user logic interface
	signal address:		std_logic_vector(ADDR_SIZE - 1 downto 0) := (others => '0');
	signal rd_data:		std_logic_vector(DATA_SIZE - 1 downto 0) := (others => '0');
	signal wr_data:		std_logic_vector(DATA_SIZE - 1 downto 0) := (others => '0');
	signal read_req:	std_logic := '0';
	signal write_req:	std_logic := '0';

	function char2slv(char: in character) return std_logic_vector is
	begin
		return std_logic_vector(to_unsigned(character'pos(char), 8));
	end function;

begin
	clk <= not clk after 10 ns;
	reset <= '1', '0' after 20 ns;

	stim: process
	begin
		tx_busy <= '0';
		rx_data <= (others => '0');
		rd_data <= x"1234";

		-- ASCII read
		wait for 100 ns;
		rx_data <= char2slv('r');
		rx_data_valid <= '1'; wait for 20 ns; rx_data_valid <= '0'; wait for 40 ns;
		rx_data <= char2slv('1');
		rx_data_valid <= '1'; wait for 20 ns; rx_data_valid <= '0'; wait for 40 ns;
		rx_data <= char2slv('2');
		rx_data_valid <= '1'; wait for 20 ns; rx_data_valid <= '0'; wait for 40 ns;
		rx_data <= char2slv('3');
		rx_data_valid <= '1'; wait for 20 ns; rx_data_valid <= '0'; wait for 40 ns;
		rx_data <= char2slv('F');
		rx_data_valid <= '1'; wait for 20 ns; rx_data_valid <= '0'; wait for 40 ns;
		rx_data <= char2slv('e');
		rx_data_valid <= '1'; wait for 20 ns; rx_data_valid <= '0'; wait for 40 ns;
		rx_data <= char2slv(LF);
		rx_data_valid <= '1'; wait for 20 ns; rx_data_valid <= '0';

		wait until tx_req = '1'; wait for 20 ns; tx_busy <= '1'; wait for 80 ns; tx_busy <= '0';
		wait until tx_req = '1'; wait for 20 ns; tx_busy <= '1'; wait for 80 ns; tx_busy <= '0';
		wait until tx_req = '1'; wait for 20 ns; tx_busy <= '1'; wait for 80 ns; tx_busy <= '0';
		wait until tx_req = '1'; wait for 20 ns; tx_busy <= '1'; wait for 80 ns; tx_busy <= '0';
		wait until tx_req = '1'; wait for 20 ns; tx_busy <= '1'; wait for 80 ns; tx_busy <= '0';
		wait for 90 ns;

		-- binary read
		rx_data <= x"00";
		rx_data_valid <= '1'; wait for 20 ns; rx_data_valid <= '0'; wait for 40 ns;
		rx_data <= x"01";
		rx_data_valid <= '1'; wait for 20 ns; rx_data_valid <= '0'; wait for 40 ns;
		rx_data <= x"23";
		rx_data_valid <= '1'; wait for 20 ns; rx_data_valid <= '0';
		
		wait until tx_req = '1'; wait for 20 ns; tx_busy <= '1'; wait for 80 ns; tx_busy <= '0';
		wait until tx_req = '1'; wait for 20 ns; tx_busy <= '1'; wait for 80 ns; tx_busy <= '0';

		-- ASCII write
		wait for 90 ns;
		rx_data <= char2slv('w');
		rx_data_valid <= '1'; wait for 20 ns; rx_data_valid <= '0'; wait for 40 ns;
		rx_data <= char2slv('1');
		rx_data_valid <= '1'; wait for 20 ns; rx_data_valid <= '0'; wait for 40 ns;
		rx_data <= char2slv('2');
		rx_data_valid <= '1'; wait for 20 ns; rx_data_valid <= '0'; wait for 40 ns;
		rx_data <= char2slv('3');
		rx_data_valid <= '1'; wait for 20 ns; rx_data_valid <= '0'; wait for 40 ns;
		rx_data <= char2slv(',');
		rx_data_valid <= '1'; wait for 20 ns; rx_data_valid <= '0'; wait for 40 ns;
		rx_data <= char2slv('a');
		rx_data_valid <= '1'; wait for 20 ns; rx_data_valid <= '0'; wait for 40 ns;
		rx_data <= char2slv('F');
		rx_data_valid <= '1'; wait for 20 ns; rx_data_valid <= '0'; wait for 40 ns;
		rx_data <= char2slv(LF);
		rx_data_valid <= '1'; wait for 20 ns; rx_data_valid <= '0';

		-- wait until write_req = '1';	-- 
		wait for 100 ns;

		-- binary write
		rx_data <= x"01";
		rx_data_valid <= '1'; wait for 20 ns; rx_data_valid <= '0'; wait for 40 ns;
		rx_data <= x"01";
		rx_data_valid <= '1'; wait for 20 ns; rx_data_valid <= '0'; wait for 40 ns;
		rx_data <= x"23";
		rx_data_valid <= '1'; wait for 20 ns; rx_data_valid <= '0'; wait for 40 ns;
		rx_data <= x"45";
		rx_data_valid <= '1'; wait for 20 ns; rx_data_valid <= '0'; wait for 40 ns;
		rx_data <= x"67";
		rx_data_valid <= '1'; wait for 20 ns; rx_data_valid <= '0';

		wait until write_req = '1';
		wait for 100 ns;
		
	end process;


	cmd_proc: entity work.cmd_proc
		generic map (
			ADDR_SIZE	=> ADDR_SIZE,
			DATA_SIZE	=> DATA_SIZE
		)
		port map (
			clk		=> clk,
			reset		=> reset,

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
			read_req	=> read_req,
			write_req	=> write_req
		);
end;
