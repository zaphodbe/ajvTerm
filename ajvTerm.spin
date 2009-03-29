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

    '' Keyboard clock and data
    kbd = 26
    kbc = 27


OBJ
    text: "VGA_1024"		' VGA Terminal Driver
    kb:	"Key"			' Keyboard driver
    ser0: "FullDuplexSerial256"	' Full Duplex Serial Controller(s)
    eeprom: "EEPROM"		' EEPROM access


VAR
    ' Terminal configuration:
    '  [baud, color, pc-port, force-7bit, cursor, auto-crlf]
    '    0      1      2          3         4        5
    long cfg[6]

    byte force7	'  force7 - Flag force to 7 bits
    byte autolf	'  autolf - Generate LF after CR
    byte state	' Main terminal emulation state
    long a0	'  Arg 0 to an escape sequence
    long a1	'   ...arg 1
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

'' Apply the currently recorded config
PUB setConfig | baud, color
    ' Extract "hot" ones into global vars
    ' pcport := cfg[2]
    force7 := cfg[3]
    autolf := cfg[5]

    ' Decode to baud and set serial ports
    baud := cfg[0]
    if (baud < 0) OR (baud > 8)
	baud := 9600
    else
	baud := baudBits[baud]
    ser0.stop
    ser0.start(r0, t0, 0, 9600)
    ' ser0.start(r0, t0, 0, baud)

    ' Set color and cursor
    color := cfg[1]
    if (color < 0) OR (color > 10)
	color := 6
    else
	color := colorBits[color]
    text.setColor(color)
    text.setCursor(cfg[4])

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

	' Strip high bit if so configured
	if force7
	    c &= $7F

	' Process char
	singleSerial0(c)

'' Set invert video based on control code
PUB setInv(c)
    if c == 1
	text.setInv(1)
    else
	text.setInv(0)

'' Take action for ANSI-style sequence
PUB ansi(c) | x, defVal

    ' Always reset input state machine at end of sequence
    state := 0

    ' Map args to appropriate default
    ' Most get a default argument of 1, a few 0.
    if (c <> "r") AND (c <> "M") AND (c <> "J") AND (c <> "m")
	if a0 == -1
	    a0 := 1
	if a1 == -1
	    a1 := 1

    case c

     "@":	' Insert char(s)
	onlast := 0
	repeat while a0--
	    text.insChar(pos)

     "d":	' Vertical position absolute
	if (a0 < 1) OR (a0 > text#rows)
	    a0 := text#rows
	pos := ((a0-1) * text#cols) + (pos // text#cols)

     "m":	' Set character enhancements
	setInv(a0)
	if a1 <> -1
	    setInv(a1)

     "A":	' Move cursor up line(s)
	repeat while a0-- > 0
	    pos -= text#cols
	    if pos < 0
		pos += text#cols
		return

     "B":	' Move cursor down line(s)
	repeat while a0-- > 0
	    pos += text#cols
	    if pos => text#chars
		pos -= text#cols
		return

     "C":	' Move cursor right
	repeat while a0-- > 0
	    pos += 1
	    if pos => text#chars
		pos -= 1
		return

     "D":	' Move cursor left
	repeat while a0-- > 0
	    pos -= 1
	    if pos < 0
		pos := 0
		return

     "G":	' Horizontal position absolute
	if (a0 < 1) OR (a0 > text#cols)
	    a0 := text#cols
	pos := (pos - (pos // text#cols)) + (a0-1)

     "H":	' Set cursor position
	if a0 == -1
	    a0 := 1
	if a1 == -1
	    a1 := 1
	pos := (text#cols * (a0-1)) + (a1 - 1)
	if pos < 0
	    pos := 0
	if pos => text#chars
	    pos := text#chars-1

     "J":	' Clear screen/EOS
	if a0 <> 1
	    ' Any arg but 1, clear whole screen
	    text.cls
	else
	    ' Otherwise clear from current position to end of screen
	    text.clEOL(pos)
	    x := pos + text#cols
	    x -= (x // text#cols)
	    repeat while x < text#chars
		text.clEOL(x)
		x += text#cols

     "K":	' Clear to end of line
	' TBD, "onlast" treatment
	text.clEOL(pos)

     "L":	' Insert line(s)
	repeat while a0-- > 0
	    text.insLine(pos)

     "M":	' Delete line(s)
	if a0 == -1
	    a0 := 0
	repeat while a0-- > 0
	    text.delLine(pos)

     "P":	' Delete char(s)
	repeat while a0--
	    text.delChar(pos)

'' Process next byte from our host port
PUB singleSerial0(c)
    case state

    ' State 0: ready for new data to display or start of escape sequence
     0:
	' Printing chars; put on screen
	if (c => 32) AND (c < 128)
	    text.putc(pos++, c)
	    if pos => text#chars
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
	    if pos => text#chars
		pos -= text#cols
		text.delLine(0)
	    return

	' Tab
	if c == 9
	    ' Advance to next tab stop
	    pos += (8 - (pos // 8))

	    ' Scroll when tab to new line
	    if pos => text#chars
		pos := text#lastline
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
	    if pos => text#chars
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

	' Unknown sequence, ignore and reset state machine
	state := 0
	return

    ' State 2: ESC-[, start decoding first numeric arg
     2:
	' Digits, assemble value
	if (c => "0") AND (c =< "9")
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
	if (c => "0") AND (c =< "9")
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
	if (c => "0") AND (c =< "9")
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
	' Set default config: 9600 baud, don't force ASCII
	'  or LF. white characters, white underscore cursor
	cfg[0] := 4
	cfg[1] := 5
	' cfg[2] := pcport := 0
	cfg[3] := force7 := 0
	cfg[4] := 5
	cfg[5] := autolf := 0

    ' Start VGA output driver
    text.start(video)
    text.cls

    ' Start Keyboard Driver
    kb.start(kbd, kbc)

    ' Initialize RS-232 ports.  We'll shortly be restarting them
    '  after we choose a config
    ser0.start(r0, t0, 0, 9600)

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
    if (key => 0) AND (key =< $7F)

	' Turn A..Z into ^A..^Z
	if ctl
	    key &= $1F

	' Emit the character
	ser0.tx(key)
	return

    ' Map keyboard driver ESC to ASCII value
    if key == $CB
	ser0.tx(27)
	return

    ' Map keyboard backspace
    if key == $C8
	ser0.tx(8)
	return

'' Display a number on the screen
'  (NB, doesn't deal with scrolling.)
PUB prn(val) | dig
    if val < 0
	text.putc(pos++, "-")
	prn(0 - val)
	return
    dig := 48 + (val // 10)
    val := val/10
    if val > 0
	prn(val)
    text.putc(pos++, dig)


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
