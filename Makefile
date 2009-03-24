# Spin source to compile
TOPSRC=ajvTerm.spin
SRCS=Basic_I2C_Driver.spin FullDuplexSerial256.spin \
    Keyboard.spin VGA_1024.spin VGA_HiRes_Text.spin

# .wav included in object
WAVS=piano.wav

term.binary: $(TOPSRC) $(SRCS) $(WAVS)
	bstc -b -o term $(TOPSRC)

clean:
	rm -f *.binary
clobber: clean
