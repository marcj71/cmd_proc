# cmd_proc -- simple command processor for a register interface

FPGA designs of any complexity can have many parts that need settings, that
provide results, or must be controlled. A register interface is a very
convenient way to read and write settings, to preload counters, or to reset
and trigger subsystems. All registers and 'actionable items' in the user
logic are given an address, and these addresses can be read/written with a
single interface. We will call this the command interface.

Any suitable frontend can be used for the command interface. Typically this
will be a UART, like the <tt>fluart</tt> that was designed hand-in-hand with
<tt>cmd_proc</tt>. Any other interface (SPI, I<sup>2</sup>C, ...) can work
als well, as long as it is byte-based. <tt>cmd_proc</tt> only works with
octets on the command side.

On the side of the user logic, one address bus, a read data bus and a write
data bus are needed. The size of the address and data buses can be specified
as a generic. The two data buses are the same size. Both sizes must be
multiples of 8 bits. Reads and writes are each acknowledged with a
single-cycle strobe on their respective control signals.

## Protocol

Four commands are supported by the <tt>cmd_proc</tt>: read and write, each
in ASCII (readable text) and binary formats. The ASCII commands are suitable
for use with a terminal program, allowing you to control the FPGA simply by
typing. Both input and output are readable strings. When under program
control, the binary commands are probably more convenient. Here, the bytes
are not translated to hexadecimal characters as they are with the ASCII
commands, but used as-is.

The format is always the same:
- a single character indicates the type of command;
- the address specifies which register must read or written;
- a read command returns the data, while a write command specifies what must
  be written.

For simplicity, the command processor does not support backspacing or
history. You could set your terminal emulator to line-buffered to solve the
first issue. Also, there is no remote echo. That means you will have to turn
on local echo if you want to see what you're typing. This is because the
command processor does not know whether you're sending text or binary
commands. It would be unusual to echo back binary data.

<dl>
<dt>ASCII read</dt>
<dd>The command has the form <tt>raaaa\n</tt>, where <tt>r</tt> or <tt>R</tt>
    indicates the ASCII read, and <tt>aaaa</tt> are the address bytes. The
    internal address buffer is initialized to 0. Any bytes specified in the
    command are shifted in from the right; any remaining leading bits will
    be 0. For example, if the address bus is 16 bits wide, four characters
    are needed to fully specify an address. To read from address 0x1234, the
    command would be <tt>r1234\n</tt>. To read from address 0x12,
    <tt>r12\n</tt> is sufficient. To read from address 0, just type
    <tt>r\n</tt>. When more bytes are given than the width of the address
    bus allows, the older ones simply drop out of the buffer:
    <tt>r123456\n</tt> will read from address 0x3456 in our example. A line
    feed character (LF, ASCII 10, 0x0a, ctrl-J) or carriage return (CR,
    ASCII 13, 0x0d, ctrl-M) ends the command. The often-used combination
    CR/LF (0x0d/0x0a) is also valid, since extra bytes are ignored. Pressing
    escape (ESC, ASCII 27, 0x1b, ctrl-[) aborts the command at any time (if
    not captured by your terminal emulator). Any whitespace in the command
    string is ignored, so if you prefer sending <tt>r 12 34\n</tt>, that
    will work. The hexadecimal bytes are case-insensitive.
    <br>The response will consist of hexadecimal bytes only. Leading zeros
    are not suppressed. The response is ended with a line feed character
    only. You may need to set your terminal emulator to translate this to
    CR/LF.</dd>

<dt>ASCII write</dt>
<dd>To write data <tt>dd</tt> to address <tt>aaaa</tt>, issue the command
    <tt>waaaa,dd\n</tt>. The same rules apply as for the read command: all
    characters are case-insensitive. Everything except valid hexadecimal
    characters, comma (ASCII 44, 0x2c), line feed and carriage return is
    ignored, allowing you to pipe in nicely-formatted strings. Address and
    data buffers are initialised to 0. Address and data bytes are filled
    from the right, extra bytes drop out on the left. Escape aborts. <br>The
    write command gives no response.</dd>

<dt>Binary read</dt>
<dd>A binary read is started by sending a null byte (NULL, ASCII 0, 0x00).
    The command processor now assumes that you know what you're doing, because
    the following bytes are used directly as the address. The right number of
    bytes must be supplied: one for an 8-bit adress, two for a 16-bit address
    and so on. The command does not have to be terminated. There is no way to
    abort the command.
    <br>The response is issued as an unterminated string of binary bytes.
    For example, a 32-bit data bus would result in four bytes, with the most
    significant byte sent first.</dd>

<dt>Binary write</dt>
<dd>A binary write starts with a binary 1 byte (SOH, ASCII 1, 0x01). The
    address and data bytes follow without separator and without ending. The
    right number of address and data bytes must be supplied. Most
    significant bytes go first.
    <br>There is no response.</dd>
</dl>

## Interface

```vhdl
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
```

<dl>
<dt><tt>ADDR_SIZE</tt> and <tt>DATA_SIZE</tt></dt>
<dd>Specify the bit widths of the internal address and data bus, respectively.
    Any size is allowed, as long as it's a multiple of eight. The model is
    based on byte (octet) transfers only.</dd>

<dt><tt>clk</tt> and <tt>reset</tt></dt>
<dd>The system clock and reset. The <tt>cmd_proc</tt> is a synchronous
    design, acting on the rising edge of the clock input. Reset is
    synchronous as well and is active high.
    <br>The UART interface is designed for the exquisitely suitable
    <tt>fluart</tt>, also on this repository.</dd>

<dt><tt>rx_data</tt> and <tt>rx_data_valid</tt></dt>
<dd>Upon reception of a valid word (i.e., start bit low and stop bit high),
    <tt>rx_data_valid</tt> must be high for one clock cycle. The data on
    <tt>rx_data</tt> will then be latched.</dd>

<dt><tt>tx_data</tt>, <tt>tx_req</tt> and <tt>tx_busy</tt></dt>
<dd><tt>tx_req</tt> is set high for one clock cycle to transmit
    <tt>tx_data</tt>. <tt>tx_busy</tt> is assumed to be high while a
    transfer is in progress. All activity will be halted while waiting for
    the interface to be ready; there is no timeout. The <tt>fluart</tt>'s
    <tt>tx_end</tt> signal is not used.
    <br>The signals controlling the user logic are kept as generic as
    possible. An example of the typical usage is also in this repository, as
    explained below.</dd>

<dt><tt>address</tt>, <tt>rd_data</tt> and <tt>wr_data</tt></dt>
<dd>The address, a <tt>std_logic_vector</tt> having <tt>ADDR_SIZE</tt> bits,
    is always sourced by <tt>cmd_proc</tt>. It is part of the command
    received on the command interface. In response to a read command,
    <tt>rd_data</tt> is the data from the user logic, after any address
    decoding. When a write command is received, the data to be written will
    be on <tt>wr_data</tt>. The two data buses are both <tt>DATA_SIZE</tt>
    bits wide. There is no slicing or shifting done in the
    <tt>cmd_proc</tt>, since it has no knowledge of what will be done with
    the data in the user logic.</dd>

<dt><tt>read_req</tt> and <tt>write_req</tt></dt>
<dd>In many cases, the data to be read will be selected using an asynchronous
    multiplexer. As long as it is done within a clock cycle, the output is
    valid. There may be cases, however, where it is convenient to know when
    the data is read. The <tt>read_req</tt> signal is provided for this
    purpose. When writing data, a strobe is indispensible. The
    <tt>write_req</tt> signal indicates that the data on <tt>wr_data</tt>
    are valid.</dd>

</dl>

## Language

For convenience, the model uses features from the VHDL2008 standard. The
<tt>all</tt> keyword saves a lot of typing and bookkeeping for non-clocked
(asynchronous) processes. VHDL2008's <tt>maximum</tt> is not supported by
Quartus yet, although all simulators understand it and the function is only
used at compile time. A similar function is given instead.

Quite some thought went into the hexadecimal-to-binary and
binary-to-hexadecimal converters. The case statements reduce to less logic
than typecasts and calculations.

## Simulation

A testbench is supplied in <tt>cmd_proc_tb.vhdl</tt>. There is no serial
port; the interface is exercised directly. The address and data buses are
both 16 bits wide. The four supported commands are given in this order:
ASCII read, binary read, ASCII write, binary write.

Use your preferred simulator. For [GHDL](http://ghdl.free.fr/), the
following commands are sufficient:

```
ghdl -c --std=08 cmd_proc.vhdl cmd_proc_tb.vhdl -r cmd_proc_tb --vcd=cmd_proc_tb.vcd --stop-time=3us
gtkwave cmd_proc_tb.vcd &
```

## Example

You'll find a synthesizable example in <tt>example_top.vhdl</tt>. The
command processor is set up for a 16-bit address bus and a 32-bit data bus.
Both are seriously oversized for the purpose, but it shows the flexibility.

A serial interface is provided, with the system clock frequency set to 50MHz
and the bit rate to 115.2kb/s. The <tt>fluart</tt> was designed for this
purpose.

The addres layout is as follows:

<dl>
<dt>address 0 (0x0000)</dt>
<dd>Always reads the constant 32-bit value 0x01020304. Writes are ignored.
    Use it to check the endianness of the receiving program. The most
    significant end is transmitted first.</dd>

<dt>address 1 (0x0001)</dt>
<dd>The lower 8 bits of the data word written to this address are placed on
    output pins. Connect these to your status LEDs. The current state of the
    pins can be read back from the same address.</dd>

<dt>address 2 (0x0002)</dt>
<dd>This is a 32-bit scratch register that can read and written. The
    contents have no effect; it's storage only.</dd>

<dt>address 256 (0x0100)</dt>
<dd>This is a 32-bit counter that is incremented by one on every system
    clock cycle. Writes have no effect. If you know the clock frequency,
    this allows you to assess the performance of the system.</dd>
</dl>

## Simplicity  

...is a goal in itself. If you have suggestions to simplify the logic and/or
improve readability of the VHDL, let me know! There are too many style
preferences to keep everyone happy, so please don't focus on indentation,
naming etcetera. Live and let live.
