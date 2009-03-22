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

    '' Video driver: set video output pin
    video = 16


    '' RS-232 driver values: PC(1) and Host(2) rx and tx lines
    r1 = 31
    t1 = 30
    r2 = 25
    t2 = 24


OBJ
    text: "VGA_1024"		' VGA Terminal Driver
    kb:	"keyboard"		' Keyboard driver
    ser: "FullDuplexSerial256"	' Full Duplex Serial Controller(s)
    ser2: "FullDuplexSerial2562"
    eeprom: "eeprom"		' EEPROM access


VAR
    ' Terminal configuration:
    '  [baud, color, pc-port, force-7bit, cursor, auto-crlf]
    '    0      1      2          3         4        5
    long cfg[6]
    pcport	'  pcport - Flag that PC port (2) is active
    force7	'  force7 - Flag force to 7 bits
    autolf	'  autolf - Generate LF after CR
    state	' Main terminal emulation state
    a0		'  Arg 0 to an escape sequence
    a1		'   ...arg 1
    onlast	' Flag that we've just put a char on last column


PUB setConfig() | baud
    ' Extract "hot" ones into global vars
    pcport := cfg[2]
    force7 := cfg[3]
    autolf := cfg[5]

    ' Decode to baud and set serial ports
    baud := baudBits(cfg[0])
    ser.stop()
    ser2.stop()
    ser.start(r1, t1, 0, baud)
    ser2.start(r2, t2, 0, baud)

    ' Set color and cursor
    text.setCursor(cfg[4])
    text.setColor(cfg[1])

PUB main()

    ' One-time setup
    init()

    ' Main loop
    repeat
	' Dispatch main keyboard and serial streams
	doKey()
	doSerial0()

	' Handling of second host serial port
	if pcport <> 0
	    doSerial1()

'' Process a byte from our PC port
PUB doSerial1() | c
    ' Look at the port for data, send to ser2 if there is
    c := ser.rxcheck
    if c < 0
	return
    ser2.tx(c)

'' Process bytes from our host port
PUB doSerial0() | c
    oldpos := pos

    ' Consume bytes until FIFO is empty
    repeat
	c := ser2.rxcheck
	if c < 0
	    ' When last of bytes is pulled, move hardware cursor
	    '  if position is changed.
	    if oldpos <> pos
		text.cursor(pos)
	    return

	' If PC port active, give it a copy
	if pcport <> 0
	    ser.tx(c)

	' Strip high bit if so configured
	if force7 <> 0
	    c &= $7F

	' Process char
	singleSerial0(c)

'' Take action for ANSI-style sequence
PUB ansi(c, a0, a1) | x
    ' Always reset input state machine at end of sequence
    state := 0

    case c

    "A":	' Move cursor up line(s)
	repeat while a0-- > 0
	    pos -= cols
	    if pos < 0
		pos += cols
		return

    "B":	' Move cursor down line(s)
	repeat while a0-- > 0
	    pos += cols
	    if pos >= chars
		pos -= cols
		return

    "C":	' Move cursor right
	repeat while a0-- > 0
	    pos += 1
	    if pos >= chars
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
	    text.cls()
	else
	    ' Otherwise clear from current position to end of screen
	    text.clEOL(pos)
	    x = pos + cols
	    x -= cols - (pos // cols)
	    repeat while x < chars
		text.clEOL(pos)

    "H":	' Set cursor position
	if a0 == -1
	    a0 := 1
	if a1 == -1
	    a1 := 1
	pos := (cols * (a0-1)) + (a1 - 1)
	if pos < 0
	    pos := 0
	if pos >= chars
	    pos := chars-1

    "K":	' Clear to end of line
	' TBD, "onlast" treatment
	text.clEOL(pos)

    "m":	' Set character enhancements
	' We just map any enhancement to be inverted text
	if a0 <> 0
	    a0 := 1
	text.inv(a0)

'' Process next byte from our host port
PUB singleSerial0(c)
    case state

    ' State 0: ready for new data to display or start of escape sequence
    0:
	' Printing chars; put on screen
	if (c >= 32) && (c < 128)
	    text.putc(pos++, c)
	    if pos >= chars
		pos = lastline
		text.delLine(0)
	    return

	' Escape sequence started
	if c == 27
	    state := 1
	    return

	' CR
	if c == 13
	    pos := pos - (pos // cols)
	    return

	' LF
	if c == 10
	    pos += cols
	    if pos >= chars
		pos -= cols
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
	    pos += cols
	    if pos >= chars
		pos -= cols
	    return

	' ESC-K, cursor left one position
	if c == "K"
	    if pos > 0
		pos -= 1
	    return

	' ESC-H, cursor up one line
	if c == "H"
	    pos -= cols
	    if pos < 0
		pos += cols
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
	    state := TBD
	    return

	' Unknown sequence, ignore
	return

    ' State 2: ESC-[, start decoding first numeric arg
    2:
	' Digits, assemble value
	if (c >= "0") && (c <= "9")
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
	ansi(c, a0, a1)
	return

    ' State 3: ESC-[<digits>;, start decoding second numeric arg
    3:
	' Digits, assemble value
	if (c >= "0") && (c <= "9")
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
	ansi(c, a0, a1)
	return

    ' State 4: ESC-[<digits>;<digits>;...  Ignore subsequent args
    4:
	if (c >= "0") && (c <= "9")
	    return
	if c == ";"
	    return
	ansi(c, a0, a1)
	return

    ' State 5: ESC-(, ignore character set selection
    5:
	state := 0
	return
    return

'' Convert baud rate index into actual bit rate
PUB baudBits(idx) : res
    if idx == 0
	res := 300
    elseif idx == 1
	res := 1200
    elseif idx == 2
	res := 1200
    elseif idx == 3
	res := 1200
    elseif idx == 4
	res := 1200
    elseif idx == 5
	res := 1200
    elseif idx == 6
	res := 1200
    elseif idx == 7
	res := 1200
    elseif idx == 8
	res := 1200
    else
	res := 9600

'' Convert color index into system color value
PUB color(idx) : res
    if idx == 0
	' TURQUOISE
	res := $29
    elseif idx == 1
	' BLUE
	res := $27
    elseif idx == 2
	' BABYBLUE
	res := $95
    elseif idx == 3
	' RED
	res := $C1
    elseif idx == 4
	' GREEN
	res := $99
    elseif idx == 5
	' GOLDBROWN
	res := $A2
    elseif idx == 6
	' WHITE
	res := $FF
    elseif idx == 7
	' HOTPINK
	res := $C9
    elseif idx == 8
	' GOLD
	res := $D9
    elseif idx == 9
	' PINK
	res := $C5
    elseif idx == 10
	' AMBERDARK
	res := $E2
    else
	' Default is turquoise
	res := 0

'' One-time initialization of terminal driver state
PUB init()
    ' Try to read EEPROM config
    if eeprom.readCfg(cfg) == 0
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

    ' Start Keyboard Driver
    kb.startx(26, 27, NUM, RepeatRate)

    ' Initialize RS-232 ports.  We'll shortly be restarting them
    '  after we choose a config
    ser.start(r1, t1, 0, 9600)
    ser2.start(r2, t2, 0, 9600)

    ' Init VGA driver
    text.start()

    ' Apply the config
    setConfig()

    ' Init state vars
    state := 0
    onlast := 0

'' Read and dispatch a keystroke
PUB doKey()
    key := kb.key								'Go get keystroke, then return here

    if key == 194 'up arrow
       ser2.str(string(27,"[A"))
    if key == 195 'down arrow
       ser2.str(string(27,"[B"))
       'ser2.out($0A)
    if key == 193 'right arrow
       ser2.str(string(27,"[C"))
    if key == 192 'left arrow
       ser2.str(string(27,"[D"))

    if key >576
       if key <603
	  key:=key-576
    if key > 608  and key < 635							'Is it a control character?
       key:=key-608
    'if key >0
    '	text.dec(key)
    if key == 200
       key:=08
    if key == 203								'Is it upper code for ESC key?
       key:= 27									'Yes, convert to standard ASCII value
    if key == 720
      Baud++									'is ESC then + then increase baud or roll over
      if Baud > 8
	 Baud:=0
      temp:=Baud
      Baud:=BR[temp]
      ser.stop
      ser2.stop
      ser.start(r1,t1,0,baud)							'ready port for PC
      ser2.start(r2,t2,0,baud)							'ready port for HOST
      Baud:=temp
      text.clsupdate(Baud,termcolor,pcport,ascii,CR)
      EEPROM
    if key == 721
       if ++termcolor > 11
	  termcolor:=1
       text.color(CLR[termcolor])
       'text.clsupdate(Baud,termcolor,pcport,ascii)
       EEPROM
    if key == 722
       if pcport == 1
	  pcport := 0
       else
	  pcport := 1
       text.clsupdate(Baud,termcolor,pcport,ascii,CR)
       EEPROM
    if key == 723
       if ascii == 0
	  ascii := 1
       else
	  ascii :=0
       text.clsupdate(Baud,termcolor,pcport,ascii,CR)
       EEPROM
    if key == 724
       curset++
       if curset > 7
	  curset := 1
       text.cursorset(curset)
       EEPROM
    if key == 725 'F6
       if CR == 1
	  CR := 0
       else
	  CR := 1
       text.clsupdate(Baud,termcolor,pcport,ascii,CR)
       EEPROM
    if key <128 and key > 0							'Is the keystroke PocketTerm compatible?    was 96
       ser2.tx(key)								'Yes, so send it
       if key == 13
       'this probably needs to be if CR == 1
	 if LNM == 1 or CR == 1'send both CR and LF?
	   ser2.tx(10)		'yes, set by LNM ESC command, send LF also

