# Miscellaneous options
CC=gcc
CFLAGS=-g

# Spin source to compile
TOPSRC=ajvTerm.spin
SRCS=Basic_I2C_Driver.spin FullDuplexSerial256.spin \
    Key.spin VGA_1024.spin VGA_HiRes_Text.spin \
    EEPROM.spin

# .wav included in object
WAVS=piano.wav

all: term.binary catseq

term.binary: $(TOPSRC) $(SRCS) $(WAVS)
	bstc -b -o term $(TOPSRC)

catseq: catseq.o
	$(CC) $(CFLAGS) -o catseq catseq.o

clean:
	rm -f *.o catseq

clobber: clean
	rm -f term.binary

STAGE=/tmp
SRC=ajvTerm-src-$(REL)
BIN=ajvTerm-$(REL)
release: term.binary
	mkdir $(STAGE)/$(SRC) ; cp * $(STAGE)/$(SRC)/
	cp term.binary $(STAGE)/$(BIN)
