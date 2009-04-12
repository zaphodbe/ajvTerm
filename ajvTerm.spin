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

    '' Geometry for config screen area
    cfgCols = 26
    cfgRows = 12


OBJ
    text: "VGA_1024"		' VGA Terminal Driver
    kb:	"Key"			' Keyboard driver
    ser0: "FullDuplexSerial256"	' Full Duplex Serial Controller(s)
    eeprom: "EEPROM"		' EEPROM access


VAR
    ' Terminal configuration:
    '  [baud, color, force-7bit, cursor, auto-crlf, caps-opt, sleep ]
    '    0      1        2          3         4        5        6
    long cfg[eeprom#CfgSize]

    byte force7	'  force7 - Flag force to 7 bits
    byte autolf	'  autolf - Generate LF after CR
    byte state	' Main terminal emulation state
    byte onlast	' Flag that we've just put a char on last column
    word pos	' Current output/cursor position
    byte caps	' Options for treatment of CAPS lock
    byte savemins ' # minutes until blank screen
    byte color	' Text color (index)
    byte baud	' Baud rate (index)
    byte cursor	' Cursor style

    ' Args to escape sequence
    long argp, a0, a1, a2
    byte narg

    ' Saved screen contents during config menu
    byte cfgScr[cfgCols*cfgRows]

    word idlesecs	' # seconds idle
    long lastsec	' CNT at time of last idlesecs tick
    byte idleoff	' Screen is turned off due to idle timeout

    byte cfgChange	' Flag that config is changed from EEPROM

    word regTop, regBot	' Scroll region top/bottom

    byte lastc		' Last displayed char


PUB main

    ' One-time setup
    init

    ' Main loop
    repeat
	' Dispatch main keyboard and serial streams
	doKey
	doSerial0

	' Run a one-second interval timer
	if not idleoff
	    if (cnt - lastsec) > clkfreq
		idlesecs += 1
		lastsec := cnt
		if idlesecs > savemins*60
		    idleoff := 1
		    text.stop


'' Apply the currently recorded config
PRI setConfig
    ' Extract "hot" ones into global vars
    force7 := cfg[2]
    autolf := cfg[4]
    caps := cfg[5]
    kb.setCaps(caps)
    savemins := cfg[6]
    if savemins < 1
	savemins := 1

    ' Decode to baud and set serial ports
    baud := cfg[0]
    if (baud < 0) OR (baud > 8)
	baud := 4
    ser0.stop
    ser0.start(r0, t0, 0, baudBits[baud])

    ' Set color and cursor
    color := cfg[1]
    if (color < 0) OR (color > 10)
	color := 6
    text.setColor(colorBits[color])
    cursor := cfg[3]
    if cursor > 8
	cursor := 5
    text.setCursor(cursor)

'' Process bytes from our host port
PRI doSerial0 | c, oldpos
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
	if (c == 13) AND autolf
	    singleSerial0(10)

'' Implement attr
PRI setInv(c)
    if c == -1
	return
    if (c < 2) OR (c => 10)
	text.setInv(0)
    else
	text.setInv(1)

'' Tell if current position is within scroll region
PRI inReg : answer
    answer := (pos => regTop) AND (pos < regBot)

'' Scroll the contents of the scroll region upward
''  (i.e., add a new blank line at the bottom of the region)
PRI scrollUp
    text.delLine(regTop)
    if regBot < text#chars
	text.insLine(regBot)

'' Scroll downward (new blank line at top)
PRI scrollDown
    if regBot < text#chars
	text.delLine(regBot)
    text.insLine(regTop)

'' Take action for ANSI-style sequence
PRI ansi(c) | x, defVal

    ' Always reset input state machine at end of sequence
    state := 0

    ' Map args to appropriate default
    ' Most get a default argument of 1, a few 0.
    if (c <> "r") AND (c <> "J") AND (c <> "m") AND (c <> "K")
	if a0 == -1
	    a0 := 1
	if a1 == -1
	    a1 := 1

    case c

     "@":	' Insert char(s)
	onlast := 0
	repeat while a0-- > 0
	    text.insChar(pos)

     "b":	' Repeat last char
	repeat while a0-- > 0
	    simplec(lastc)

     "d":	' Vertical position absolute
	if (a0 < 1) OR (a0 > text#rows)
	    a0 := text#rows
	pos := ((a0-1) * text#cols) + (pos // text#cols)

     "m":	' Set character enhancements
	if a0 == -1
	    a0 := 0
	setInv(a0)
	setInv(a1)
	setInv(a2)

     "r":	' Set scroll region
	' TBD is to change all the scroll code to check the region

	' Bound param to screen geometry
	if a0 < 1
	    a0 := 1
	elseif a0 > text#cols
	    a0 := text#cols
	if a1 < 1
	    a1 := 1
	elseif a1 > text#cols
	    a1 := text#cols
	if a1 < a0
	    a1 := a0

	' Set region; regTop is first location in the scroll region;
	'  regBot is first location beyond end of scroll region.
	regTop := (a0-1) * text#cols
	regBot := a1 * text#cols

	' This op seems to implicitly home the cursor...
	pos := 0

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
	    if onlast
		onlast := 0
	    else
		pos -= 1
		if pos < 0
		    pos := 0
			return

     "G":	' Horizontal position absolute
	if (a0 < 1) OR (a0 > text#cols)
	    a0 := text#cols
	pos := (pos - (pos // text#cols)) + (a0-1)

     "H":	' Set cursor position
	onlast := 0
	if a0 =< 0
	    a0 := 1
	if a1 =< 0
	    a1 := 1
	pos := (text#cols * (a0-1)) + (a1 - 1)
	if pos < 0
	    pos := 0
	if pos => text#chars
	    pos := text#chars-1

     "J":	' Clear screen/EOS
	' Erase to top of screen
	if a0 == 1
	    text.clBOL(pos)
	    x := pos - text#cols
	    x -= x // text#cols
	    repeat while x => 0
		text.clEOL(x)
		x -= text#cols
	    return

	' Erase whole screen and home cursor
	if a0 == 2
	    pos := 0

	' Clear from current position to end of screen
	text.clEOL(pos)
	x := pos + text#cols
	x -= (x // text#cols)
	repeat while x < text#chars
	    text.clEOL(x)
	    x += text#cols

     "K":	' Clear parts of line
	' If we're beyond the end of the line, advance to the next
	'  line if there *is* one.  This lets the clearing apply to
	'  the line we're kinda sorta "on".
	if onlast
	    pos += 1
	    if pos < text#chars
		onlast := 0
	    else
		pos -= 1

	if a0 == -1		' No arg, to end of line
	    text.clEOL(pos)
	elseif a0 == 1		' 1 == from beginning to position
	    text.clBOL(pos)
	else			' 2 == clear whole line
	    text.clEOL(pos - (pos // text#cols))


     "L":	' Insert line(s)
	if inReg
	    repeat while a0-- > 0
		if regBot < text#chars
		    text.delLine(regBot)
		text.insLine(pos)

     "M":	' Delete line(s)
	if inReg
	    repeat while a0-- > 0
		text.delLine(pos)
		if regBot < text#chars
		    text.insLine(regBot)

     "P":	' Delete char(s)
	repeat while a0--
	    text.delChar(pos)

     "S":	' Scroll upward
	if (pos => regTop) AND (pos < regBot)
	    repeat while a0--
		scrollUp

'' Alternate ANSI escape sequence: Esc-[?<num><letter>
PRI ansi2(c)
    state := 0
    case c
     "h":
	if a0 < 1
	    a0 := 0
	kb.setKeys(a0)

'' Put a single printing char onto the screen
PRI simplec(c)

    ' If we put to last position on line last time,
    ' advance position for new output.
    if onlast
	pos += 1
	if pos == regBot
	    scrollUp
	    pos -= text#cols
	onlast := 0

    ' Put the actual text
    text.putc(pos++, lastc := c)

    ' Delay motion at end of line until next output char
    if (pos // text#cols) == 0
	pos -= 1
	onlast := 1

'' Process next byte from our host port
PRI singleSerial0(c) | x
    case state

    ' State 0: ready for new data to display or start of escape sequence
     0:
	' Assume high bit chars are alternate character set
	'  output, and make them consume a space
	if c > 127
	    c := $20

	' Printing chars; put on screen
	if c => 32
	    simplec(c)
	    return

	' Escape sequence started
	if c == 27
	    state := 1
	    return

	' CR
	if c == 13
	    pos := pos - (pos // text#cols)
	    onlast := 0
	    return

	' LF
	if c == 10
	    if inReg
		pos += text#cols
		if pos => regBot
		    scrollUp
		    pos -= text#cols
	    else
		pos += text#cols
		if pos => text#chars
		    pos -= text#cols
	    return

	' Tab
	if c == 9
	    ' Advance to next tab stop
	    onlast := 0
	    pos += (8 - (pos // 8))

	    ' Scroll when tab to new line
	    if pos => text#chars
		pos := text#lastline
		text.delLine(0)
	    return

	' Backspace
	if c == 8
	    if pos > 0
		if onlast
		    onlast := 0
		else
		    pos -= 1
	    return

    ' State 1: ESC received, ready for escape sequence
     1:
	case c

	 ' ESC-[, start of extended ANSI style arguments
	 "[":
	    narg := 1
	    longfill(@a0, -1, 3)
	    state := 2
	    return

	 ' ESC-P, cursor down one line
	 "P":
	    pos += text#cols
	    if pos => text#chars
		pos -= text#cols

	 ' ESC-K, cursor left one position
	 "K":
	    if pos > 0
		pos -= 1

	 ' ESC-H, cursor up one line
	 "H":
	    pos -= text#cols
	    if pos < 0
		pos += text#cols

	 ' ESC-D, scroll one line
	 "D":
	    if inReg
		scrollUp

	 ' ESC-M, scroll backward
	 "M":
	    if inReg
		scrollDown

	 ' ESC-G, cursor home
	 "G":
	    onlast := pos := 0

	 ' ESC-(, char set selection (decoded and ignored)
	 "(":
	    state := 5
	    return

	' Escape sequence done, reset state machine
	state := 0

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
	    argp := @a1
	    narg := 2
	    state := 3
	    return

	' "?", variant ANSI sequence
	if c == "?"
	    state := 6
	    return

	' End of input sequence
	ansi(c)

    ' State 3: ESC-[<digits>;, start decoding subsequent numeric args
     3:
	' Digits, assemble value
	if (c => "0") AND (c =< "9")
	    if narg < 4
		x := LONG[argp]
		if x == -1
		    x := c - "0"
		else
		    x := (x*10) + (c - "0")
		LONG[argp] := x
	    return

	' Semicolon, next arg
	if c == ";"
	    narg += 1
	    argp += 4
	    return

	' End of sequence
	ansi(c)

    ' State 4: unused

    ' State 5: ESC-(, ignore character set selection
     5:
	state := 0

    ' State 6: Esc-[?<num><letter>
     6:
	' Digits, assemble value
	if (c => "0") AND (c =< "9")
	    if a0 == -1
		a0 := c - "0"
	    else
		a0 := (a0*10) + (c - "0")
	    return
	ansi2(c)

'' One-time initialization of terminal driver state
PRI init
    ' Try to read EEPROM config
    eeprom.initialize
    if eeprom.readCfg(@cfg) == 0
	' Set default config: 9600 baud, don't force ASCII
	'  or LF. white characters, white underscore cursor
	'  CAPS lock with its usual function.
	cfg[0] := 4
	cfg[1] := 6
	cfg[2] := force7 := 0
	cfg[3] := 5
	cfg[4] := autolf := 0
	cfg[5] := caps := 0
	cfg[6] := savemins := 2
	cfgChange := 1
    else
	cfgChange := 0

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
    regTop := 0
    regBot := text#chars

'' Read and dispatch a keystroke
PRI doKey | key, ctl
    ' Get actual keystroke from driver
    key := kb.key
    if key == 0
	return

    ' Handle idle timeouts
    idlesecs := 0
    if idleoff
	idleoff := 0
	text.start(video)
	text.setColor(colorBits[color])
	text.setCursor(cursor)

    ' See if it's a request for config mode
    '  (ESC with the control key down)
    if key == 27
	if kb.checkCtl
	    config
	    return

    ' Emit the character
    ser0.tx(key)

'' Display a number on the screen
'  (NB, doesn't deal with scrolling.)
PRI prn2(val) | dig
    dig := 48 + (val // 10)
    val := val/10
    if val > 0
	prn2(val)
    text.putc(pos++, dig)
PRI prn(val)
    text.putc(pos++, " ")
    if val < 0
	text.putc(pos++, "-")
	val := 0 - val
    prn2(val)
PRI putn(r, c, val)
    pos := r * text#cols + c
    prn(val)

'' Write a string into the screen
PRI puts(row, col, str) | x, ptr
    ptr := (row * text#cols) + col
    repeat x from 0 to STRSIZE(str)-1
	text.putc(ptr++, BYTE[str+x])

'' Write current config to screen
PRI cfgPaint | x
    text.fillBox(0, 0, cfgRows, cfgCols, " ")
    puts(0, 0, @cfgHead)
    repeat x from 1 to CfgRows-1
	text.putc(x * text#cols, "|")
	text.putc(x * text#cols + 25, "|")
    puts(1, 2, string("Configuration"))

    puts(2, 3, string("F1 - Baud"))
    putn(2, 12, baudBits[baud])

    puts(3, 3, string("F2 - Color"))
    putn(3, 13, color)

    puts(4, 3, string("F3 - 8 bit"))
    if force7
	puts(4, 8, string("7"))

    puts(5, 3, string("F4 - auto LF"))
    if not autolf
	puts(5, 16, string("off"))

    puts(6, 3, string("F5 - CAPS =="))
    if caps == 0
	puts(6, 16, string("normal"))
    elseif caps == 1
	puts(6, 16, string("ctl"))
    else
	puts(6, 16, string("swap Ctl"))

    puts(7, 3, string("F6 - Screen save xm"))
    putn(7, 19, savemins)

    puts(8, 3, string("F7 - Cursor"))
    putn(8, 14, cursor)

    puts(9, 3, string("ENTER - save config"))
    puts(10, 3, string("Esc - done"))
    puts(11, 0, @cfgHead)

'' Decode ANSI keyboard sequence into:
'   0 - Unknown
'   1..n - F1-Fn
'  -1 - Enter
'  -2 - Escape
PRI cfgGetKey : val | c
    c := kb.getkey

    ' ENTER
    if c == 13
	val := -1
	return

    ' If not ESC, it's a stray key to be ignored
    if c <> 27
	val := 0
	return

    ' ESC is an escape sequence if the rest of the bytes of
    '  the sequence are already in the queue.
    c := kb.key
    if c == 0
	' No bytes, so it's a plain typed ESC
	val := -2
	return

    ' Get next byte of sequence
    ' ESC-O[P..X] maps to F1..F9
    if c == "O"
	c := kb.key
	if (c => "P") AND (c =< "X")
	    val := c - "O"
	    return

    ' Unknown
    val := 0

'' Process one keystroke for the config menu.
'' Return 1 if config mode done, otherwise 0
PRI cfgKey : doneflag | c
    doneflag := 0

    c := cfgGetKey
    case c

     -1:	' Enter - save to EEPROM
	if cfgChange
	    eeprom.writeCfg(@cfg)
	    cfgChange := 0
	return

     -2:	' ESC - end of config mode
	doneflag := 1
	return

     1:		' F1 - cycle baud rates
	baud += 1
	if baud > 8
	    baud := 0
	cfg[0] := baud
	ser0.stop
	ser0.start(r0, t0, 0, baudBits[baud])

     2:		' F2 - cycle colors
	color += 1
	if color > 10
	    color := 0
	cfg[1] := color
	text.setColor(colorBits[color])

     3:		' F3 - toggle masking of 8th bit
	force7 := force7 ^ 1
	cfg[2] := force7

     4:		' F4 - toggle auto add of LF
	autolf := autolf ^ 1
	cfg[4] := autolf

     5:		' F5 - cycle CAPS lock treatment
	caps += 1
	if caps > 2
	    caps := 0
	kb.setCaps(caps)
	cfg[5] := caps

     6:		' F6 - cycle screen saver timeout
	savemins *= 2
	if savemins > 10
	    savemins := 1
	cfg[6] := savemins

     7:		' F7 - cycle cursor style
	cursor += 1
	if cursor > 8
	    cursor := 0
	text.setCursor(cursor)
	cfg[3] := cursor

    ' Common case for all config changes
    cfgChange := 1


'' Interact with the user to set the terminal configuration
PRI config | ignore, oldpos
    oldpos := pos
    text.setCursorPos(8*text#cols + 16)
    text.saveBox(@cfgScr, 0, 0, cfgRows, cfgCols)
    repeat
	cfgPaint
    until cfgKey
    text.restoreBox(@cfgScr, 0, 0, cfgRows, cfgCols)
    pos := oldpos
    text.setCursorPos(pos)

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

    '' Config header
    cfgHead byte "+========================+", 0
