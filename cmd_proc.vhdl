-- cmd_proc: a simple command processor for a register interface, inspired
-- by https://opencores.org/projects/uart_fpga_slow_control (or on github:
-- https://github.com/freecores/uart_fpga_slow_control)
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


entity cmd_proc is
	generic (
		ADDR_SIZE:	natural := 16;	-- bits, in multiples of 8!
		DATA_SIZE:	natural := 16
	);
	port (
		clk:		in  std_logic;
		reset:		in  std_logic;

		-- UART interface
		rx_data:	in  std_logic_vector(7 downto 0);
		rx_data_valid:	in  std_logic;

		tx_data:	out std_logic_vector(7 downto 0);
		tx_req:		out std_logic;
		tx_busy:	in  std_logic;

		-- user logic interface
		address:	out std_logic_vector(ADDR_SIZE - 1 downto 0);
		rd_data:	in  std_logic_vector(DATA_SIZE - 1 downto 0);
		wr_data:	out std_logic_vector(DATA_SIZE - 1 downto 0);
		read_req:	out std_logic;
		write_req:	out std_logic
	);
end;


architecture rtl of cmd_proc is
	constant ADDR_MAX8: integer := ADDR_SIZE / 8;	-- binary access
	constant DATA_MAX8: integer := DATA_SIZE / 8;
	constant ADDR_MAX4: integer := ADDR_SIZE / 4;	-- ASCII access
	constant DATA_MAX4: integer := DATA_SIZE / 4;

	-- for synthesizers not supporting VHDL2008's maximum function yet
	function maximum_int(a: integer; b: integer) return integer is
	begin
		if a > b then
			return a;
		else
			return b;
		end if;
	end function;


	type state_t is (idle, asc_read, asc_write, bin_read, bin_write);

	signal proc_state, proc_state_n: state_t;
	signal pc, pc_n: integer range 0 to 7 := 0;	-- program counter
	signal bc, bc_n: integer range 0 to maximum_int(ADDR_MAX4, DATA_MAX4) + 1 := 0;	-- byte counter

	signal address_i, address_n: std_logic_vector(ADDR_SIZE - 1 downto 0) := (others => '0');
	signal wr_data_i, wr_data_n: std_logic_vector(DATA_SIZE - 1 downto 0) := (others => '0');
	signal rd_data_i, rd_data_n: std_logic_vector(DATA_SIZE - 1 downto 0) := (others => '0');
	
	signal tx_req_i, tx_req_n: std_logic := '0';

	signal rx_num: std_logic_vector(3 downto 0) := (others => '0');
	signal rx_char: character := NUL;


	function slv2char(byte: std_logic_vector) return character is
	begin
		return character'val(to_integer(unsigned(byte)));
	end function;


	function char2slv(char: in character) return std_logic_vector is
	begin
		return std_logic_vector(to_unsigned(character'pos(char), 8));
	end function;


	-- 329 LE
-- 	function char2int(char: in character) return integer is
-- 	begin
-- 		return character'pos(char);
-- 	end function;

-- 	function topnibble2hex(word: std_logic_vector) return std_logic_vector is
-- 		variable val: integer;
-- 	begin
-- 		val := to_integer(unsigned(word(word'left downto word'left - 3)));
-- 		if val <= 9 then
-- 			return std_logic_vector(to_unsigned(val + char2int('0'), 8));
-- 		else
-- 			return std_logic_vector(to_unsigned(val - 10 + char2int('a'), 8));
-- 		end if;
-- 	end function;


	-- 314 LE
	function nibble2hex(nibble: std_logic_vector(3 downto 0)) return std_logic_vector is
	begin
		case nibble is
		when x"0"   => return char2slv('0');
		when x"1"   => return char2slv('1');
		when x"2"   => return char2slv('2');
		when x"3"   => return char2slv('3');
		when x"4"   => return char2slv('4');
		when x"5"   => return char2slv('5');
		when x"6"   => return char2slv('6');
		when x"7"   => return char2slv('7');
		when x"8"   => return char2slv('8');
		when x"9"   => return char2slv('9');
		when x"a"   => return char2slv('a');
		when x"b"   => return char2slv('b');
		when x"c"   => return char2slv('c');
		when x"d"   => return char2slv('d');
		when x"e"   => return char2slv('e');
		when x"f"   => return char2slv('f');
		when others => return char2slv('?');	-- should never happen
		end case;
	end function;

begin

	ascii_decoder: with slv2char(rx_data) select rx_num <=
		x"0" when '0',
		x"1" when '1',
		x"2" when '2',
		x"3" when '3',
		x"4" when '4',
		x"5" when '5',
		x"6" when '6',
		x"7" when '7',
		x"8" when '8',
		x"9" when '9',
		x"a" when 'a' | 'A',
		x"b" when 'b' | 'B',
		x"c" when 'c' | 'C',
		x"d" when 'd' | 'D',
		x"e" when 'e' | 'E',
		x"f" when 'f' | 'F',
		(others => '0') when others;

	rx_char <= slv2char(rx_data);


	cmd_registers: process(clk)
	begin
		if rising_edge(clk) then
			if reset = '1' then
				proc_state  <= idle;
				pc          <= 0;
				bc          <= 0;
				address_i   <= (others => '0');
				wr_data_i   <= (others => '0');
				rd_data_i   <= (others => '0');
				tx_req_i    <= '0';
			else
				proc_state  <= proc_state_n;
				pc          <= pc_n;
				bc          <= bc_n;
				address_i   <= address_n;
				wr_data_i   <= wr_data_n;
				rd_data_i   <= rd_data_n;
				tx_req_i    <= tx_req_n;
			end if;
		else
		end if;
	end process;

	-- outputs
	address  <= address_i;
	wr_data  <= wr_data_i;
	tx_req   <= tx_req_i;


	rx_proc: process(all)
	begin
		-- defaults
		proc_state_n <= proc_state;
		pc_n         <= pc;
		bc_n         <= bc;
		address_n    <= address_i;
		wr_data_n    <= wr_data_i;
		rd_data_n    <= rd_data_i;
		read_req     <= '0';
		write_req    <= '0';
		tx_data      <= (others => '0');
		tx_req_n     <= '0';

		case proc_state is
		when idle =>
			if rx_data_valid = '1' then
				case rx_char is
				when 'r' | 'R' =>
					-- read data, ASCII
					proc_state_n <= asc_read;
				when 'w' | 'W' =>
					-- write data, ASCII
					proc_state_n <= asc_write;
				when NUL =>
					-- x"00": read data, binary
					proc_state_n <= bin_read;
				when SOH =>
					-- x"01": write data, binary
					proc_state_n <= bin_write;
				when others =>
					-- huh?
					proc_state_n <= idle;
				end case;
			end if;

			pc_n      <= 0;
			bc_n      <= 0;
			address_n <= (others => '0');
			rd_data_n <= (others => '0');
			wr_data_n <= (others => '0');

		when asc_read =>
			case pc is
			when 0 =>
				-- Read any number of hex digits, shifting them from right to
				-- left in the address buffer. The buffer is initialised to 0,
				-- so no input is OK. Extra bytes just drop out of the buffer on
				-- the left side. Terminate with line feed (ASCII 10). Non-hex
				-- digits such as spaces and tabs are ignored.
				if rx_data_valid = '1' then
					case rx_char is
					when ESC =>
						proc_state_n <= idle;

					when LF | CR =>
						read_req <= '1';
						pc_n     <= pc + 1;

					when '0' to '9' | 'a' to 'f' | 'A' to 'F' =>
						address_n <= address_i(address_i'left - 4 downto 0) & rx_num;

					when others =>
						null;

					end case;
				end if;

			when 1 =>
				-- register data
				rd_data_n <= rd_data;
				pc_n      <= pc + 1;

			when 2 =>
				-- return data
				if tx_busy = '0' and tx_req = '0' then
					tx_req_n  <= '1';
				end if;

				if tx_req = '1' then
					rd_data_n <= rd_data_i(rd_data_i'left - 4 downto 0) & x"0";
					bc_n      <= bc + 1;
				end if;

				if bc = DATA_MAX4 then
					pc_n      <= pc + 1;
				end if;

				tx_data <= nibble2hex(rd_data_i(rd_data_i'left downto rd_data_i'left - 3));

			when 3 =>
				-- add a line feed
				tx_data <= char2slv(LF);

				if tx_busy = '0' and tx_req = '0' then
					tx_req_n <= '1';
				end if;

				if tx_req = '1' then
					pc_n <= pc + 1;
				end if;

			when others =>
				proc_state_n <= idle;

			end case;

		when bin_read =>
			case pc is
			when 0 =>
				-- read address
				if rx_data_valid = '1' then
					address_n <= address_i(address_i'left - 8 downto 0) & rx_data;
					bc_n      <= bc + 1;
				end if;

				if bc = ADDR_MAX8 then
					read_req  <= '1';
					bc_n      <= 0;
					pc_n      <= pc + 1;
				end if;

			when 1 =>
				-- register data
				rd_data_n <= rd_data;
				pc_n      <= pc + 1;

			when 2 =>
				-- return data
				if tx_busy = '0' and tx_req = '0' then
					tx_req_n  <= '1';
				end if;

				if tx_req = '1' then
					rd_data_n <= rd_data_i(rd_data_i'left - 8 downto 0) & x"00";
					bc_n      <= bc + 1;
				end if;

				if bc = DATA_MAX8 then
					pc_n      <= pc + 1;
				end if;

				tx_data <= rd_data_i(rd_data'left downto rd_data'left - 7);

			when others =>
				proc_state_n <= idle;

			end case;

		when asc_write =>
			case pc is
			when 0  =>
				-- Read any number of hex digits, shifting them from right to
				-- left in the address/data buffers. The buffer is initialised
				-- to 0, so no input is OK. Extra bytes just drop out of the
				-- buffer on the left side. Terminate address with comma (ASCII
				-- 44), data with line feed (ASCII 10). Non-hex digits such as
				-- spaces and tabs are ignored.
				if rx_data_valid = '1' then
					case rx_char is
					when ESC =>
						proc_state_n <= idle;

					when ',' =>
						pc_n <= pc + 1;

					when '0' to '9' | 'a' to 'f' | 'A' to 'F' =>
						address_n <= address_i(address_i'left - 4 downto 0) & rx_num;

					when others =>
						null;

					end case;
				end if;

			when others =>
				if rx_data_valid = '1' then
					case rx_char is
					when ESC =>
						proc_state_n <= idle;

					when LF | CR =>
						write_req    <= '1';
						proc_state_n <= idle;

					when '0' to '9' | 'a' to 'f' | 'A' to 'F' =>
						wr_data_n <= wr_data_i(wr_data_i'left - 4 downto 0) & rx_num;

					when others =>
						null;

					end case;
				end if;

			end case;

		when bin_write =>
			case pc is
			when 0 => 
				-- read address
				if rx_data_valid = '1' then
					address_n <= address_i(address_i'left - 8 downto 0) & rx_data;
					bc_n      <= bc + 1;
				end if;

				if bc = ADDR_MAX8 then
					read_req  <= '1';
					bc_n      <= 0;
					pc_n      <= pc + 1;
				end if;

			when 1 =>
				if rx_data_valid = '1' then
					wr_data_n <= wr_data_i(wr_data_i'left - 8 downto 0) & rx_data;
					bc_n      <= bc + 1;
				end if;

				if bc = DATA_MAX8 then
					read_req  <= '1';
					pc_n      <= pc + 1;
				end if;


			when others =>
				write_req    <= '1';
				proc_state_n <= idle;

			end case;

		when others =>
			proc_state_n <= idle;

		end case;

	end process;

end;
