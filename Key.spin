'' ***************************************
'' *  PS/2 Keyboard Driver v1.0.1	 *
'' *  Author: Chip Gracey		 *
'' *  Made Spin-centric by Andy Valencia *
'' *  Copyright (c) 2004 Parallax, Inc.	 *
'' *  See end of file for terms of use.	 *
'' ***************************************

VAR
    long cog1		' Cog ID (plus 1) running keyboard
    long tail		' Index (0..15) for next byte in rx[]

    long nkey		' # values in keys[]
    long keyhd, keytl	' FIFO indices for keys[]

    ' Parameters passed to the cog:
    long dpin, cpin	' Data/Clock pins to use
    byte rx[16]		' FIFO of bytes from keyboard
    byte tx		' Next byte to send to keyboard

    byte keys[16]	' Decoded ASCII keystrokes
    byte shiftL, shiftR	' Flags for right and left shift keys held
    byte ctl		'  ...control key
    byte capsLock	'  ...CAPS lock held
    byte numLock	'  ...num lock held
    byte alt		'  ...ALT key
    byte isE0, isF0	'  Extended key sequence prefixes received

'' Start keyboard driver - starts a cog
'' returns false if no cog available
''
''   dpin  = data signal on PS/2 jack
''   cpin  = clock signal on PS/2 jack
''
''     use 100-ohm resistors between pins and jack
''     use 10K-ohm resistors to pull jack-side signals to VDD
''     connect jack-power to 5V, jack-gnd to VSS
PUB start(dp, cp) : okay
    dpin := dp
    cpin := cp
    okay := cog1 := cognew(@entry, @dpin)+1
    nkey := keyhd := keytl := tail := 0
    shiftL := shiftR := ctl := capsLock := numLock := alt := isE0 := 0

'' Stop keyboard driver - frees a cog
PUB stop
    if cog1
	cogstop(cog1~ -  1)

'' Add a char to the FIFO
PRI enq(c)
    if nkey == 16
	return
    keys[keyhd++] := c
    nkey += 1
    keyhd &= $F

'' Process an actual keyboard data character.
' Things like shift key changes don't reach here.
PRI procRX3(ch) | sh, c
    ' Drop char if no room in FIFO
    if nkey == 16
	return

    ' Shift is considred held if either or both shift keys are down
    sh := shiftL | shiftR

    ' Map using base map
    c := tab[ch]

    ' Use shifted tabs[] if:
    '	- CAPS lock and shift not held for an alphabetic key
    '	- No CAPS lock, and shift held
    if capsLock
	if (sh == 0) AND ((c => "a") AND (c =< "z"))
	    c := tabs[ch]
    elseif sh
	 c:= tabs[ch]

    ' Key with no action
    if c == 0
	return

    ' Map control chars
    if ctl
	c &= $1F

    ' Put in FIFO
    enq(c)

'' Output an ESC, then the given string
PRI escstr(s) | xx
    enq(27)
    repeat xx from 0 to STRSIZE(s)
	enq(s[xx])

'' Handle FN keys
PRI fnkey(c) : processed | s
    processed := 1
    case c
     $5:	' F1
	s := string("OP")
     $6:	' F2
	s := string("OQ")
     $4:	' F3
	s := string("OR")
     $C:	' F4
	s := string("OS")
     $3:	' F5
	s := string("OT")
     $B:	' F6
	s := string("OU")
     $83:	' F7
	s := string("OV")
     $A:	' F8
	s := string("OW")
     $1:	' F9
	s := string("OX")
     $9:	' F10
	s := string("[21~")
     $78:	' F11
	s := string("[23~")
     $7:	' F12
	s := string("[24~")
     OTHER:
	processed := 0
	return
    escstr(s)

'' Handle cursor keys
PRI cursor_key(c) : processed | s
    processed := 1
    case c
     $75:	' Up
	s := string("OA")
     $72:	' Down
	s := string("OB")
     $74:	' Right
	s := string("OC")
     $6B:	' Left
	s := string("OD")
     $75:	' Page Up
	s := string("[5~")
     $72:	' Page Down
	s := string("[6~")
     $70:	' Insert
	s := string("[2~")
     $71:	' Delete
	s := string("[3~")
     $6C:	' Home
	s := string("OH")
     $69:	' End
	s := string("OF")
     OTHER:
	processed := 0
	return

    ' Output ESC, then sequence for the key
    escstr(s)

'' Handle shift keys
PRI shift_key(c) : processed | kval
    processed := 1
    kval := 1-isF0
    case c
     $12:
	shiftL := kval
     $59:
	shiftR := kval
     $14:
	ctl := kval
     $11:
	alt := kval
     $58:
	if isF0
	    capsLock := capsLock ^ 1
     OTHER:
	processed := 0

'' Update our state machine with another scancode from the keyboard
PRI procRX2(c)
    if shift_key(c)
	return

    ' Ignore unmappable chars, and key releases
    if isF0 OR (c => $80)
	return

    if cursor_key(c)
	return

    if fnkey(c)
	return

    procRX3(c)

'' Process any pending scancode bytes from the low level keyboard
''  software UART driver.  Bytes move out of rx[] and decoded ASCII
''  values are placed in keys[].
PRI procRX | c
    ' Consume bytes from rx[].  The low level driver, running on its
    '  own cog, puts (non-zero) bytes into slots in rx[] as they are
    '  presented by the keyboard.  It knows that we have consumed a
    '  slot when we set the slot's position back to zero.
    repeat while (c := rx[tail])
	' Take next char and process
	rx[tail++] := 0
	tail &= $F

	' Note prefixes
	if c == $E0
	    isE0 := 1
	elseif c == $F0
	    isF0 := 1
	else
	    ' Process actual data byte
	    procRX2(c)

	    ' And clear prefixes
	    isE0 := isF0 := 0

'' Get key (never waits)
'' returns key (0 if buffer empty)
PUB key : c
    procRX
    c := 0
    if nkey
	nkey -= 1
	c := keys[keytl]
	keys[keytl++] := 0
	keytl &= $F

'' Get next key (may wait for keypress)
'' returns key
PUB getkey : c
    repeat until (c := key)

'' Clear key buffer
PUB clearkeys
    repeat until key == 0

'' Clear buffer and get new key (always waits for keypress)
'' returns key
PUB newkey : c
    clearkeys
    c := getkey

'' Check if any key in buffer
'' returns t|f
PUB gotkey : truefalse
    truefalse := nkey > 0

DAT

'******************************************
'* Assembly language PS/2 keyboard driver *
'******************************************

			org

'
' Entry
'
			' Load input parameters _dpin/_cpin
entry			movd	:par,#_dpin
			mov	x,par
			mov	y,#2
:par			rdlong	0,x
			add	:par,dlsb
			add	x,#4
			djnz	y,#:par

			mov	dmask,#1		' Set pin masks
			shl	dmask,_dpin
			mov	cmask,#1
			shl	cmask,_cpin

			' Modify port registers within code
			test	_dpin,#$20	wc
			muxc	_d1,dlsb
			muxc	_d2,dlsb
			muxc	_d3,#1
			muxc	_d4,#1
			test	_cpin,#$20	wc
			muxc	_c1,dlsb
			muxc	_c2,dlsb
			muxc	_c3,#1

			' Reset output parameter _head
			mov	_head,#0

'
' Reset keyboard
'
			' Reset directions
reset			mov	dira,#0
			mov	dirb,#0

			' Send reset command to keyboard
			mov	data,#$FF
			call	#transmit

'
' Get scancode
'
			' Receive byte from keyboard
loop			call	#receive

'
'
' Enter scancode into buffer
'
			' Point to next position in rx[] to be used
			mov	x,par
			add	x,#8
			add	x,_head
			rdbyte	y,x

			' If old data is not removed yet, drop
			'  this byte
			test	y,#$FF		wz
	if_nz		jmp	#loop

			' Put byte in place
			wrbyte	data,x

			' Advance FIFO head pointer
			add	_head,#1
			and	_head,#$F

			jmp	loop

'
' Transmit byte to keyboard
'
transmit
_c1			or	dira,cmask		'pull clock low
			movs	napshr,#13		'hold clock for ~128us (must be >100us)
			call	#nap
_d1			or	dira,dmask		'pull data low
			movs	napshr,#18		'hold data for ~4us
			call	#nap
_c2			xor	dira,cmask		'release clock

			test	data,#$0FF	wc	'append parity and stop bits to byte
			muxnc	data,#$100
			or	data,dlsb

			mov	x,#10			'ready 10 bits
transmit_bit		call	#wait_c0		'wait until clock low
			shr	data,#1		wc	'output data bit
_d2			muxnc	dira,dmask
			mov	wcond,c1		'wait until clock high
			call	#wait
			djnz	x,#transmit_bit		'another bit?

			mov	wcond,c0d0		'wait until clock and data low
			call	#wait
			mov	wcond,c1d1		'wait until clock and data high
			call	#wait

			call	#receive_ack		'receive ack byte with timed wait
			cmp	data,#$FA	wz	'if ack error, reset keyboard
	if_nz		jmp	#reset

transmit_ret		ret

'
' Receive byte from keyboard
'
receive			test	_cpin,#$20	wc	'wait indefinitely for initial clock low
			waitpne cmask,cmask
receive_ack
			mov	x,#11			'ready 11 bits
receive_bit		call	#wait_c0		'wait until clock low
			movs	napshr,#16		'pause ~16us
			call	#nap
_d3			test	dmask,ina	wc	'input data bit
			rcr	data,#1
			mov	wcond,c1		'wait until clock high
			call	#wait
			djnz	x,#receive_bit		'another bit?

			shr	data,#22		'align byte
			test	data,#$1FF	wc	'if parity error, reset keyboard
	if_nc		jmp	#reset
rand			and	data,#$FF		'isolate byte

look_ret
receive_ack_ret
receive_ret		ret

'
' Wait for clock/data to be in required state(s)
'
wait_c0			mov	wcond,c0		'(wait until clock low)

wait			mov	y,tenms			'set timeout to 10ms

wloop			movs	napshr,#18		'nap ~4us
			call	#nap
_c3			test	cmask,ina	wc	'check required state(s)
_d4			test	dmask,ina	wz	'loop until got state(s) or timeout
wcond	if_never	djnz	y,#wloop		'(replaced with c0/c1/c0d0/c1d1)

			tjz	y,#reset		'if timeout, reset keyboard
wait_ret
wait_c0_ret		ret


c0	if_c		djnz	y,#wloop		'(if_never replacements)
c1	if_nc		djnz	y,#wloop
c0d0	if_c_or_nz	djnz	y,#wloop
c1d1	if_nc_or_z	djnz	y,#wloop

'
' Nap
'
nap			rdlong	t,#0			'get clkfreq
napshr			shr	t,#18/16/13		'shr scales time
			min	t,#3			'ensure waitcnt won't snag
			add	t,cnt			'add cnt to time
			waitcnt t,#0			'wait until time elapses (nap)

nap_ret			ret

'
' Initialized data
'
'
dlsb			long	1 << 9
tenms			long	10_000 / 4

'' Base table, mapping scancodes to chars
tab	byte	0, 0, 0, 0, 0, 0, 0, 0		' 0
	byte	0, 0, 0, 0, 0, 9, "`", 0	' 8
	byte	0, 0, 0, 0, 0, "q", "1", 0	' 16
	byte	0, 0, "zsaw2", 0		' 24
	byte	0, "cxde43", 0			' 32
	byte	0, " vftr5", 0			' 40
	byte	0, "nbhgy6", 0			' 48
	byte	0, 0, "mju78", 0		' 56
	byte	0, ",kio09", 0			' 64
	byte	0, "./l;p-", 0, 0		' 72
	byte	0, 39, 0, "[=", 0, 0, 0		' 80
	byte	0, 13, "]", 0, 92, 0, 0, 0	' 88
	byte	0, 0, 0, 0, 0, 8, 0, 0		' 96
	byte	0, 0, 0, 0, 0, 0, 0, 0		' 104
	byte	0, 0, 0, 0,			' 108
	byte	0, 27, 0, 0			' 112
	byte	"+3-*9", 0, 0			' 120

'' Mapping of scancodes when shift is held
tabs	byte	0, 0, 0, 0, 0, 0, 0, 0		' 0
	byte	0, 0, 0, 0, 0, 9, "~", 0	' 8
	byte	0, 0, 0, 0, 0, "Q", "!", 0	' 16
	byte	0, 0, "ZSAW@", 0		' 24
	byte	0, "CXDE$#", 0			' 32
	byte	0, " VFTR%", 0			' 40
	byte	0, "NBHGY^", 0			' 48
	byte	0, 0, "MJU&*", 0		' 56
	byte	0, "<KIO)(", 0			' 64
	byte	0, ">?L:P_", 0, 0		' 72
	byte	0, 34, 0, "{+", 0, 0, 0		' 80
	byte	0, 13, "}", 0, "|", 0, 0, 0	' 88
	byte	0, 0, 0, 0, 0, 0, 8, 0		' 96
	byte	0, 0, 0, 0, 0, 0, 0, 0		' 104
	byte	0, 0, 0, 0,			' 108
	byte	0, 0, 27, 0			' 112
	byte	0, "+3-*9", 0, 0		' 120
'
' Uninitialized data
'
dmask			res	1
cmask			res	1
data			res	1
x			res	1
y			res	1
t			res	1

_head			res	1	' Our index into rx[]
_dpin			res	1	' Configured data and clock pins
_cpin			res	1

{{


						   TERMS OF USE: MIT License														  

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation     
files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,    
modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software
is furnished to do so, subject to the following conditions:								      
															      
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
															      
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE	      
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR	      
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,   
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.			      

}}
