'' EEPROM.spin
''	Routines for reading/writing config to EEPROM via I2C


CON
    '' Saved config in EEPROM
    EEPROMAddr = %1010_0000
    EEPROM_Base = $7FE0

    '' I2C access to EEPROM
    i2cSCL = 28


OBJ
  i2c:	"basic_i2c_driver"	' I2C serial bus


VAR
    byte init
    long cfg[6]


'' Read the configuration
'' "params" points to an array of 6 words:
''   [baud, color, pc-port, force-7bit, cursor, auto-crlf]
'' Return value is 1 if a config is available, 0 if not.
PUB readCfg(params) : res2 | loc, x
    '' One-time setup for I2C access
    if init == 0
	i2c.Initialize(i2cSCL)
	init := 1

    '' Start at base of config, see if there's a config
    loc := EEPROM_Base
    x := i2c.ReadByte(i2cSCL, EEPROMAddr, loc)
    res2 := 0
    if x <> 55
	return

    '' There is.  Get the config values.  They are read into a
    ''  sequence of memory locations which mirrors how they
    ''  will lie in the array "params".
    repeat x from 0 to 5
	loc += 4
	cfg[x] := i2c.ReadLong(i2cSCL, EEPROMAddr, loc)

    '' Success; move result to caller's memory and return success
    longmove(params, @cfg, 6)
    res2 := 1
    waitcnt(clkfreq/200 + cnt)

'' Write a config back to EEPROM
'' ("params" is as above.)
'' This routine assumes a readCfg() will always precede this write
PUB writeCfg(params) | loc, x
    longmove(@cfg, @params, 6)
    loc := EEPROM_Base
    i2c.WriteLong(i2cSCL, EEPROMAddr, loc, 55)
    repeat x from 0 to 5
	loc += 4
	i2c.WriteLong(i2cSCL, EEPROMAddr, loc, params[x])
    waitcnt(clkfreq/200 + cnt)
