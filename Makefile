# Spin source to compile
TOPSRC=ajvTerm.spin
SRCS=Basic_I2C_Driver.spin FullDuplexSerial256.spin \
    FullDuplexSerial2562.spin Keyboard.spin \
    VGA_1024.spin VGA_HiRes_Text.spin

# .wav included in object
WAVS=piano.wav

ajvTerm.binary: $(TOPSRC) $(SRCS) $(WAVS)
	bstc -b $(TOPSRC)

FullDuplexSerial2562.spin: FullDuplexSerial256.spin
	cp FullDuplexSerial256.spin FullDuplexSerial2562.spin
