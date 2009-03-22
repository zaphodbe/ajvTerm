'' ajvTerm.spin
''	VT-100 emulation
''
'' Based on code from Vince Briel
'' VT-100 code from Jeff Ledger
''
''		Current VT-100 Code list
''
''	ESC[m			Turn off character attributes
''	ESC[0m			Turn off character attributes
''	ESC[1m			Turn bold character on (reverse)
''	ESC[7m			Turn reverse video on
''	ESC[nA			Move cursor up n lines
''	ESC[nB			Move cursor down n lines
''	ESC[nC			Move cursor right n lines
''	ESC[nD			Move cursor left n lines
''	ESC[H			Move cursor to upper left corner
''	ESC[;H			Move cursor to upper left corner
''	ESC[line;columnH	Move cursor to screen location v,h
''	ESC[f			Move cursor to upper left corner
''	ESC[;f			Move cursor to upper left corner
''	ESC[line;columnf	Move cursor to sceen location v,h
''	ESCD			Move/scroll window up one line
''	ESC[D			Move/scroll window up one line
''	ESCL			Move/scroll window up one line (undocumented)
''	ESC[L			Move/scroll window up one line (undocumented)
''	ESCM			Move/scroll window down one line
''	ESCK			Clear line from cursor right
''	ESC[0K			Clear line from cursor right
''	ESC[1K			Clear line from cursor left
''	ESC[2K			Clear entire line
''	ESC[J			Clear screen from cursor down
''	ESC[0J			Clear screen from cursor down
''	ESC[1J			Clear screen from cursor up
''	ESC[2J			Clear entire screen
''	ESC[0c			Terminal ID responds with [?1;0c
''	ESC[c			 (ditto)
''
'' List of ignored codes
''
''	ESC[xxh			All of the ESC[20h thru ESC[?9h commands
''	ESC[xxl			All of the ESC[20i thru ESC[?9i commands
''	ESC=			Alternate keypad mode
''	ESC<			Enter/Exit ANSI mode
''	ESC>			Exit Alternate keypad mode
''	Esc5n			Device status report
''	Esc0n			Response: terminal is OK
''	Esc3n			Response: terminal is not OK
''	Esc6n			Get cursor position
''	EscLine;ColumnR		Response: cursor is at v,h
''	Esc#8			Screen alignment display
''	Esc[2;1y		Confidence power up test
''	Esc[2;2y		Confidence loopback test
''	Esc[2;9y		Repeat power up test
''	Esc[2;10y		Repeat loopback test
''	Esc[0q			Turn off all four leds
''	Esc[1q			Turn on LED #1
''	Esc[2q			Turn on LED #2
''	Esc[3q			Turn on LED #3
''	Esc[4q			Turn on LED #4


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
    long cfg[6]
    pcport	'  pcport - Flag that PC port (2) is active
    force7	'  force7 - Flag force to 7 bits
    autolf	'  autolf - Generate LF after CR


PUB setConfig() | baud
    ' Extract "hot" ones into global vars
    pcport := cfg[2]
    force7 := cfg[3]
    autolf := cfg[5]

    ' Decode to baud and set serial ports
    baud := baudBits(cfg[0])

PUB main | state, c


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

    ' Apply the config
    setConfig()

  XXX this goes in apply of config

  Baud:=tempbaud
  text.cls(Baud,termcolor,pcport,ascii,CR)
'  text.clsupdate(Baud,termcolor,pcport,ascii,CR)
  text.inv(0)
  text.cursorset(curset)
  vt100:=0
  repeat
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



'' END keyboard console routine



'LOOK FOR SERIAL INPUT HERE
    if pcport == 0								'Is PC turned on at console for checking?
       remote2 := ser.rxcheck							'Yes, look at the port for data
       if (remote2 > -1)							'remote = -1 if no data
	  ser2.tx(remote2)							'Send the data out to the host device
	  waitcnt(clkfreq/200 + cnt)						'Added to attempt eliminate dropped characters
    remote := ser2.rxcheck							'Look at host device port for data
    if (remote > -1)
       if ascii == 1 'yes force 7 bit ascii
	  if (remote > 127)
	     remote := remote -128
       if pcport == 0
	  ser.tx(remote)
'Start of VT100 code
      if remote == 27											'vt100 ESC code is being sent
	 vt100:=1
	 byte1:=0
	 byte2:=0
	 byte3:=0
	 byte4:=0
	 byte5:=0
	 byte6:=0
	 byte7:=0
	 remote:=0
	 temp2:=0											'Don't display the ESC code
      if remote == 99 and vt100 == 1
	 remote:=0
	 vt100:=0
	 text.cls(Baud,termcolor,pcport,ascii,CR)
      if remote == 61 and vt100 == 1										  'lool for ESC=
	 vt100:= remote := 0


      'put ESC D and ESC M here
      if remote == 77 and vt100 == 1 'AKA ESC M
	 text.scrollM
	 vt100 := 0
      if remote == 68 and vt100 == 1 'AKA ESC D
	 if byte2 <> 91 and byte3 <> 91 and byte4 <> 91  'not esc[D
	    'text.scrollD
	    vt100 := 0
      if remote == 76 and vt100 == 1 'AKA ESC L
      if remote == 91 and vt100 == 1									'look for open bracket [
	 vt100:=2											'start recording code
      if remote == 62 and vt100 == 1 or remote == 60 and vt100 == 1					'look for < & >
	 vt100:=0 ' not sure why this is coming up, can't find in spec.
      if vt100==2 ''Check checking for VT100 emulation codes
	 if remote > 10
	   byte7:=byte6
	   byte6:=byte5											' My VTCode Mini Buffer
	   byte5:=byte4
	   byte4:=byte3
	   byte3:=byte2											'Record the last 7 bytes
	   byte2:=byte1
	   byte1:=remote

	 if remote == 109										'look for lowercase m
	    if byte2 == 91										'if [m turn off to normal set
	       text.inv(0)
	       vt100:=0
	    if byte2 == 49 and vt100 > 0									      'is it ESC[1m BOLD
	       text.inv(1)
	       vt100 := 0
	    if byte2  == 55 and vt100 > 0									      'is it ESC[7m?
	       text.inv(1)
	       vt100 := 0
	    if byte2  == 48 and vt100 > 0									      '0 is back to normal
	       text.inv(0)
	       vt100:=0


	 if remote == 104										'look for lowercase h set CR/LF mode
	    if byte2 == 48 'if character before h is 0 maybe command is 20h
	       if byte3 == 50 'if byte3 then it is for sure 20h
		 LNM := 0
	    vt100:=0

	 if remote == 61										'lool for =
	    vt100:=0

	 if remote == 114										'look for lowercase r
	    vt100:=0

	 if remote == 108										'look for lowercase l
	    if byte2 == 48 'if character before l is 0 maybe command is 20l
	       if byte3 == 50 'if byte3 then it is for sure 20l
		 LNM := 1  '0 means CR/LF in CR mode only
	    vt100:=0

	 if remote == 62  'look for >
	    vt100:=0
	 if remote == 77										'ESC M look for obscure scroll window code
	    text.scrollM
	    vt100:=0
	 'if remote == 68 or remote == 76 ' look for ESC D  or ESC L
	 '   text.scrollD
	 '   vt100:=0
	 if remote == 72 or remote == 102								' HOME CURSOR (uppercase H or lowercase f)
	    if byte2==91 or byte2==59									'look for [H or [;f maybe [xx;H
	       if byte5 == 91 'then esc[nn;H
		  byte4:=byte4-48
		  byte3:=byte3-48
		  byte4:=byte4*10
		  byte4:=byte4+byte3
		  var1 := byte4
		  loop:=0
		  col:=0 'new code
		  text.cursloc(col,row)
		  'text.cursrow(var1)
		  vt100:=0
	       else
		  text.home
		  vt100:=0
	    '' Check for X & Y with [H or ;f   -   Esc[Line;ColumnH

	    else											'here remote is either H or f
	      if byte4 == 59										'is col is greater than 9     ; ALWAYS if byte4=59
		byte3:=byte3-48										'Grab 10's
		byte2:=byte2-48										'Grab 1's
		byte3:=byte3*10										'Multiply 10's
		byte3:=byte3+byte2									'Add 1's
		col:=byte3										'Set cols

		if byte7 == 91										'Assume row number is greater than 9  if ; at byte 4 and [ at byte 7 greater than 9
		   byte6:=byte6-48									'Grab 10's
		   byte5:=byte5-48									'Grab 1's
		   byte6:=byte6*10									'Multiply 10's
		   byte6:=byte6+byte5									'Add 1's
		   row:=byte6

		if byte6 == 91										'Assume row number is less than 10
		   byte5:=byte5 - 48									'Grab 1's
		   row:=byte5

	      if byte3 == 59										' Assume that col is less an 10
		byte2:=byte2-48										'Grab 1's
		col:=byte2										'set cols

		if byte6 == 91										'Assume row number is greater than 9
		   byte5:=byte5-48									'Grab 10's
		   byte4:=byte4-48									'Grab 1's
		   byte5:=byte5*10									'Multiply 10's
		   byte5:=byte5+byte4									'Add 1's
		   row:=byte5
		if byte5 == 91										'Assume that col is greater than 10
		   byte4:=byte4-48									 'Grab 1's
		   row:=byte4
	      else
		 if byte5:=59 'then ESC[nn;nnnH too far! read variable for row and make col max at 80
		    col:= 80 'max it can be
		    byte7:=byte7-48									 'Grab 10's
		    byte6:=byte6-48									 'Grab 1's
		    byte7:=byte7*10									 'Multiply 10's
		    byte7:=byte7+byte6									 'Add 1's
		    row:=byte7

	      col:=col-1
	      if row == -459
		 row:=1
	      if col == -40    ' Patches a bug I havn't found.	*yet*
		 col := 58     ' A Microsoft approach to the problem. :)
	      if row == -449
		 row := 2      ' Appears to be an issue with reading
	      if row == -439   ' single digit rows.
		 row := 3
	      if row == -429   ' This patch checks for the bug and replaces
		 row := 4      ' the faulty calculation.
	      if row == -419
		 row := 5      ' Add to list to find the source of bug later.
	      if row == -409
		 row := 6
	      if row == -399
		 row := 7
	      if row == -389
		 row := 8
	      if row == -379
		 row := 9

	      if row < 0
		 row:=0
	      if col < 0
		 col:=0
	      if row > 35
		 row :=35
	      if col > 79
		 col := 79

	      text.cursloc(col,row)
	    vt100:=0
	 if remote == 114	'ESCr

	       text.out(126)
	 if remote == 74    '' CLEAR SCREEN
	    if byte2==91    '' look for [J  '' clear screen from cursor to 25
	       text.clsfromcursordown
	    'vt100:=0
	    if byte2==50    '' look for [2J '' clear screen
	       text.cls(Baud,termcolor,pcport,ascii,CR)
	    if byte2==49     'look for [1J
	       text.clstocursor
	    if byte2==48     'look for [0J
	       text.clsfromcursordown
	    vt100:=0
	 if remote == 66    '' CURSOR DOWN    Esc[ValueB
	    if byte4 == 91 '' Assume number over 10
	      byte3:=byte3-48
	      byte2:=byte2-48
	      byte3:=byte3*10
	      byte3:=byte3+byte2
	      var1:=byte3
	    if byte3 == 91 '' Assume number is less 10
	      byte2:=byte2-48
	      var1:=byte2
	    if byte2 == 91 ''ESC[B no numbers move down one
	      'text.out($C3)
	      var1 := 1
	    loop:=0
	    repeat until loop == var1
	       loop++
	       text.out($C3)

	    vt100:=0


	 if remote == 65    '' CURSOR UP   Esc[ValueA
	    if byte4 == 91 '' Assume number over 10
	      byte3:=byte3-48
	      byte2:=byte2-48
	      byte3:=byte3*10
	      byte3:=byte3+byte2
	      var1:=byte3
	    if byte3 == 91 '' Assume number is less 10
	      byte2:=byte2-48
	      var1:=byte2
	    if byte2 == 91 ''ESC[A no numbers move down one

	      var1 := 1
	    loop:=0
	    repeat until loop == var1
	       text.out($C2)
	       loop++
	    vt100:=0


	 if remote == 67    '' CURSOR RIGHT   Esc[ValueC
	    if byte4 == 91 '' Assume number over 10
	      byte3:=byte3-48
	      byte2:=byte2-48
	      byte3:=byte3*10
	      byte3:=byte3+byte2
	      var1:=byte3
	    if byte3 == 91 '' Assume number is less 10
	      byte2:=byte2-48
	      var1:=byte2
	    if byte2 == 91 ''ESC[C no numbers move RIGHT one

	      var1 := 1
	    loop:=0
	    repeat until loop == var1
	       text.out($C1)
	       loop++
	    vt100:=0

	 if remote == 68    '' CURSOR LEFT   Esc[ValueD  OR ESC[D
	    if byte4 == 91 '' Assume number over 10
	      byte3:=byte3-48
	      byte2:=byte2-48
	      byte3:=byte3*10
	      byte3:=byte3+byte2
	      var1:=byte3
	    if byte3 == 91 '' Assume number is less 10
	      byte2:=byte2-48
	      var1:=byte2
	    if byte2 == 91 ''ESC[D no numbers move LEFT one

	      var1 := 1
	    loop:=0
	    repeat until loop == var1
	       text.out($C0)   'was $C0
	       loop++
	    vt100:=0

	 if remote == 75   '' Clear line  Esc[K
	   if byte2 == 91 '' Look for [
	     text.clearlinefromcursor

	     vt100:=0
	   if byte2  == 48 ' look for [0K
	      if byte3 == 91
		 text.clearlinefromcursor

		 vt100:=0
	   if byte2 == 49  ' look for [1K
	      if byte3 == 91
		 text.clearlinetocursor
		 vt100 := 0
	   if byte2 == 50 ' look for [2K
	      if byte3 == 91
		 text.clearline

		 vt100 := 0

	 if remote == 99 ' look for [0c or [c		ESC [ ? 1 ; Ps c Ps=0 for VT-100 no options
	   if byte2 == 91 '' Look for [
		ser2.str(string(27,"[?1;0c"))
		vt100 := 0
	   if byte2 == 48
		if byte3 == 91
		     ser2.str(string(27,"[?1;0c"))
		     vt100 := 0
	 remote:=0 '' hide all codes from the VGA output.

      if record == 13 and remote == 13	''LF CHECK
	 if CR == 1
	   text.out(remote)
	 remote :=0
      if remote == 08
	 remote := $C0	  'now backspace just moves cursor, doesn't clear character
      if remote > 8
	 text.out(remote)
      record:=remote ''record last byte

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

