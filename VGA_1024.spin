'' VGA_1024.spin
''
'' Modified by Andy Valencia while redesigning PockeTerm code
'' MODIFIED BY VINCE BRIEL FOR POCKETERM FEATURES
'' MODIIFED BY JEFF LEDGER / AKA OLDBITCOLLECTOR
''

CON
    cols = 80			' Number of screen columns
    lcols = cols/4		'  ...counted in longs
    rows = 40			'  ...rows
    chars = rows*cols		' # of screen characters
    lchars = chars/4		'  ...counted in longs
    lastline = (rows-1)*cols	' Index to beginning of last line
    GOLDBLUE = $08F0		' Color value for gold on blue
    CYANBLUE = $2804		'  ...cyan on blue


OBJ
    vga : "VGA_HiRes_Text"	' The physical VGA driver


VAR
    byte screen[chars]		' Screen character buffer
    word colors[rows]		' Color specs for each screen
				'  (description in VGA_HiRes_Text.spin)
    byte cursor[6]		' Cursor info array (see CursorPtr
				'  description in VGA_HiRes_Text.spin)
    long sync			' Sync used by VGA routine,
    byte inverse		' Flag for painting inverse chars
    byte tmpl[cols]		' Temp buffer for a line


PUB start(BasePin) | i, char

    ' Start vga
    vga.start(BasePin, @screen, @colors, @cursor, @sync)
    waitcnt(clkfreq * 1 + cnt)	'wait 1 second for cogs to start

    ' Init screen colors to gold on blue
    setColor(GOLDBLUE)

    '' Init cursor to underscore with slow blink
    cursor[2] := %110

    '' No inverse
    inverse := 0

PUB stop
    vga.stop

'' Set color information for display
PUB setColor(val)
    wordfill(@colors, val, rows)

'' Set value of "inverse char" flag
PUB setInv(c)
    inverse := c

'' Set type of cursor
PUB setCursor(c) | i
    i:=%000
    if c == 1
	i:= %001
    elseif c == 2
	i:= %010
    elseif c == 3
	i:= %011
    elseif c == 4
	i:= %101
    elseif c == 5
	i:= %110
    elseif c == 6
	i:= %111
    elseif c == 7
	i:= %000
    cursor[2] := i

'' Clear screen
PUB cls
    longfill(@screen, $20202020, lchars)

'' Clear to end of line
PUB clEOL(pos) | count
    count := cols - (pos // cols)
    bytefill(@screen + pos, $20, count)

'' Clear to beginning of line
PUB clBOL(pos) | count
    count := pos // cols
    bytefill(@screen + pos - count, $20, count)

'' Delete line at position
PUB delLine(pos) | src, count
    ' Move back to start of line
    pos -= pos // cols

    ' Point to next line
    src := pos + cols

    ' Calculate # of longs to move
    count := (chars - src) / 4

    ' Copy lines to close this line's position
    if count > 0
	longmove(@screen + pos, @screen + src, count)

    ' Blank last line
    longfill(@screen + lastline, $20202020, lcols)

'' Clear from position to end of screen
PUB clEOS(pos)
    cleol(pos)
    pos += cols - (pos // cols)
    repeat while pos < chars
	longfill(@screen + pos, $20202020, lcols)
	pos += cols

'' Update cursor position
PUB setCursorPos(pos)
    cursor[0] := pos // cols
    cursor[1] := pos / cols

'' Insert a line before this position
PUB insLine(pos) | base, nxt
    base := pos - (pos // cols)
    pos := lastline
    repeat while pos > base
	nxt := pos - cols
	longmove(@screen + pos, @screen + nxt, lcols)
	pos := nxt
    clEOL(base)

'' Insert a char at the given position
PUB insChar(pos) | count
    ' Due to ripple effect, we buffer to tmpl[], then move back
    count := (cols - (pos // cols)) - 1
    bytemove(@tmpl, @screen + pos, count)
    screen[pos] := " "
    bytemove(@screen + pos + 1, @tmpl, count)

'' Delete char at given position
PUB delChar(pos) | count
    count := (cols - (pos // cols)) - 1
    bytemove(@screen + pos, @screen + pos + 1, count)
    screen[pos + count] := " "

'' Put a char at the named position
PUB putc(pos, c)
    if inverse
	c |= $80
    screen[pos] := c

'' Write a box of screen memory to the caller's buffer
PUB saveBox(dest, row, col, nrow, ncol) | x, ptr
    ptr := @screen + row*cols + col
    repeat x from 0 to nrow-1
	bytemove(dest, ptr, ncol)
	dest += ncol
	ptr += cols

'' Read a box of screen memory from the caller's buffer
PUB restoreBox(src, row, col, nrow, ncol) | x, ptr
    ptr := @screen + row*cols + col
    repeat x from 0 to nrow-1
	bytemove(ptr, src, ncol)
	src += ncol
	ptr += cols

'' Fill a box of screen memory with this value
PUB fillBox(row, col, nrow, ncol, val) | x, ptr
    ptr := @screen + row*cols + col
    repeat x from 0 to nrow-1
	bytefill(ptr, val, ncol)
	ptr += cols
