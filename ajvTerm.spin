'' ajvTerm.spin
''	VT-100 emulation
''
'' Based on code from Vince Briel

CON
    _clkmode = xtal1 + pll16x
    _xinfreq = 5_000_000

    '' Parameters for keyboard driver: disable num lock, set repeat rate
    NUM = %100
    RepeatRate = %01_01000

    '' Video driver: video output pin
    video = 16


    '' RS-232 driver values: Host(0) and PC (1) rx and tx lines
    r0 = 25
    t0 = 24
    r1 = 31
    t1 = 30


OBJ
    text: "VGA_1024"		' VGA Terminal Driver
    kb:	"keyboard"		' Keyboard driver
    ser0: "FullDuplexSerial256"	' Full Duplex Serial Controller(s)
    ser1: "FullDuplexSerial2562"
    eeprom: "EEPROM"		' EEPROM access


VAR
    ' Terminal configuration:
    '  [baud, color, pc-port, force-7bit, cursor, auto-crlf]
    '    0      1      2          3         4        5
    long cfg[6]

    byte pcport	'  pcport - Flag that PC port (2) is active
    byte force7	'  force7 - Flag force to 7 bits
    byte autolf	'  autolf - Generate LF after CR
    byte state	' Main terminal emulation state
    byte a0	'  Arg 0 to an escape sequence
    byte a1	'   ...arg 1
    byte onlast	' Flag that we've just put a char on last column
    word pos	' Current output/cursor position


PUB main

    ' One-time setup
    init

    ' Main loop
    repeat
	' Dispatch main keyboard and serial streams
	doKey
	doSerial0

	' Handling of second host serial port
	if pcport
	    doSerial1

'' Apply the currently recorded config
PUB setConfig | baud, color
    ' Extract "hot" ones into global vars
    pcport := cfg[2]
    force7 := cfg[3]
    autolf := cfg[5]

    ' Decode to baud and set serial ports
    baud := cfg[0]
    if (baud < 0) OR (baud > 8)
	baud := 9600
    else
	baud := baudBits[baud]
    { TBD, after I add the UI for setting config
    ser0.stop
    ser1.stop
    ser0.start(r0, t0, 0, baud)
    ser1.start(r1, t1, 0, baud)
    }

    ' Set color and cursor
    color := cfg[1]
    if (color < 0) OR (color > 10)
	color := 6
    else
	color := colorBits[color]
    text.setColor(color)
    text.setCursor(cfg[4])

'' Process a byte from our PC port
PUB doSerial1 | c
    ' Look at the port for data, send to ser0 if there is
    c := ser1.rxcheck
    if c < 0
	return
    ser0.tx(c)

'' Process bytes from our host port
PUB doSerial0 | c, oldpos
    oldpos := pos

    ' Consume bytes until FIFO is empty
    repeat
	c := ser0.rxcheck
	if c < 0
	    ' When last of bytes is pulled, move hardware cursor
	    '  if position is changed.
	    if oldpos <> pos
		text.setCursorPos(pos)
	    return

	' If PC port active, give it a copy
	if pcport
	    ser1.tx(c)

	' Strip high bit if so configured
	if force7
	    c &= $7F

	' Process char
	singleSerial0(c)

'' Take action for ANSI-style sequence
PUB ansi(c) | x

    ' Always reset input state machine at end of sequence
    state := 0

    case c

     "A":	' Move cursor up line(s)
	repeat while a0-- > 0
	    pos -= text#cols
	    if pos < 0
		pos += text#cols
		return

     "B":	' Move cursor down line(s)
	repeat while a0-- > 0
	    pos += text#cols
	    if pos >= text#chars
		pos -= text#cols
		return

     "C":	' Move cursor right
	repeat while a0-- > 0
	    pos += 1
	    if pos >= text#chars
		pos -= 1
		return

     "D":	' Move cursor left
	repeat while a0-- > 0
	    pos -= 1
	    if pos < 0
		pos := 0
		return

     "L":	' Insert line(s)
	repeat while a0-- > 0
	    text.insLine(pos)

     "M":	' Delete line(s)
	repeat while a0-- > 0
	    text.delLine(pos)

     "@":	' Insert char(s)
	onlast := 0
	repeat while a0--
	    text.insChar(pos)

     "P":	' Delete char(s)
	repeat while a0--
	    text.delChar(pos)

     "J":	' Clear screen/EOS
	if a0 <> 1
	    ' Any arg but 1, clear whole screen
	    text.cls
	else
	    ' Otherwise clear from current position to end of screen
	    text.clEOL(pos)
	    x := pos + text#cols
	    x -= text#cols - (pos // text#cols)
	    repeat while x < text#chars
		text.clEOL(pos)

     "H":	' Set cursor position
	if a0 == -1
	    a0 := 1
	if a1 == -1
	    a1 := 1
	pos := (text#cols * (a0-1)) + (a1 - 1)
	if pos < 0
	    pos := 0
	if pos >= text#chars
	    pos := text#chars-1

     "K":	' Clear to end of line
	' TBD, "onlast" treatment
	text.clEOL(pos)

     "m":	' Set character enhancements
	' We just map any enhancement to be inverted text
	if a0
	    a0 := 1
	text.setInv(a0)

'' Process next byte from our host port
PUB singleSerial0(c)
    case state

    ' State 0: ready for new data to display or start of escape sequence
     0:
	' Printing chars; put on screen
	if (c >= 32) AND (c < 128)
	    text.putc(pos++, c)
	    if pos >= text#chars
		pos := text#lastline
		text.delLine(0)
	    return

	' Escape sequence started
	if c == 27
	    state := 1
	    return

	' CR
	if c == 13
	    pos := pos - (pos // text#cols)
	    return

	' LF
	if c == 10
	    pos += text#cols
	    if pos >= text#chars
		pos -= text#cols
		text.delLine(0)
	    return

	' Backspace
	if c == 8
	    if pos > 0
		pos -= 1
	    return

    ' State 1: ESC received, ready for escape sequence
     1:
	' ESC-[, start of extended ANSI style arguments
	if c == "["
	    a0 := a1 := -1
	    state := 2
	    return

	' ESC-P, cursor down one line
	if c == "P"
	    pos += text#cols
	    if pos >= text#chars
		pos -= text#cols
	    return

	' ESC-K, cursor left one position
	if c == "K"
	    if pos > 0
		pos -= 1
	    return

	' ESC-H, cursor up one line
	if c == "H"
	    pos -= text#cols
	    if pos < 0
		pos += text#cols
	    return

	' ESC-D, scroll one line
	if c == "D"
	    text.delLine(0)
	    return

	' ESC-M, scroll backward
	if c == "M"
	    text.insLine(0)
	    return

	' ESC-G, cursor home
	if c == "G"
	    pos := 0
	    return

	' ESC-(, char set selection (decoded and ignored)
	if c == "("
	    state := 5
	    return

	' Unknown sequence, ignore
	return

    ' State 2: ESC-[, start decoding first numeric arg
     2:
	' Digits, assemble value
	if (c >= "0") AND (c <= "9")
	    if a0 == -1
		a0 := c - "0"
	    else
		a0 := (a0*10) + (c - "0")
	    return

	' Semicolon, advance to arg1
	if c == ";"
	    state := 3
	    return

	' End of input sequence
	ansi(c)
	return

    ' State 3: ESC-[<digits>;, start decoding second numeric arg
     3:
	' Digits, assemble value
	if (c >= "0") AND (c <= "9")
	    if a1 == -1
		a1 := c - "0"
	    else
		a1 := (a1*10) + (c - "0")
	    return

	' Semicolon, ignore subsequent args
	if c == ";"
	    state := 4
	    return

	' End of sequence
	ansi(c)
	return

    ' State 4: ESC-[<digits>;<digits>;...  Ignore subsequent args
     4:
	if (c >= "0") AND (c <= "9")
	    return
	if c == ";"
	    return
	ansi(c)
	return

    ' State 5: ESC-(, ignore character set selection
     5:
	state := 0
	return
    return

'' One-time initialization of terminal driver state
PUB init
    ' Try to read EEPROM config
    if eeprom.readCfg(@cfg) == 0
	' Set default config: 9600 baud, pcport OFF, don't force ASCII
	'  or LF. white characters, white underscore cursor
	cfg[0] := 4
	cfg[1] := 5
	cfg[2] := pcport := 0
	cfg[3] := force7 := 0
	cfg[4] := 5
	cfg[5] := autolf := 0

    ' Start VGA output driver
    text.start(video)
    text.cls

    ' Start Keyboard Driver
    kb.startx(26, 27, NUM, RepeatRate)

    ' Initialize RS-232 ports.  We'll shortly be restarting them
    '  after we choose a config
    ser0.start(r0, t0, 0, 9600)
    ser1.start(r1, t1, 0, 9600)

    ' Apply the config
    setConfig

    ' Init state vars
    state := 0
    onlast := 0
    pos := 0

'' Read and dispatch a keystroke
PUB doKey | key, ctl
    ' Get actual keystroke from driver
    key := kb.key
    if key == 0
	return

    ' Pick off flags
    ctl := 0
    if key & $200
	ctl := 1
    key &= $FF

    ' up/down/right/left arrow keys
    if key == 194
	ser0.str(string(27,"[A"))
	return
    if key == 195
	ser0.str(string(27,"[B"))
	return
    if key == 193
	ser0.str(string(27,"[C"))
	return
    if key == 192
	ser0.str(string(27,"[D"))
	return

    ' Printing char?
    if (key >= " ") AND (key <= $7F)

	' Turn A..Z into ^A..^Z
	if ctl
	    if (key >= "A") AND (key <= "Z")
		key -= $40

	' Emit the character
	ser0.tx(key)
	return

    ' Map keyboard driver ESC to ASCII value
    if key == $CB
	ser0.tx(27)
	return


DAT
    '' Convert baud rate index into actual bit rate
    '              0    1     2     3     4      5      6      7      8
    baudBits long 300, 1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200


    '' Map color index into system color value
    '               0       1       2       3     4       5
    '           TURQUOISE, BLUE, BABYBLUE, RED, GREEN, GOLDBROWN
    colorBits byte $29,    $27,     $95,   $C1,  $99,    $A2

    '               6       7      8     9        10
    '             WHITE, HOTPINK, GOLD, PINK, AMBERDARK
              byte $FF,    $C9,   $D9,  $C5,     $A5
