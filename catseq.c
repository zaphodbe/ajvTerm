/*
 * catseq.c
 *	Output escape sequences a few at a time
 *
 * Usage is: catseq <trace-file> [ <log-file> ]
 *
 * Each time you hit a key, the output is emitted through the next
 *  escape sequence.  If <log-file> is specified, the output is also
 *  put into this file (this lets you step out to a problematic
 *  sequence, and then have a trace file just to that point).
 * If you type the digits 1-9, it actually outputs that many sequences
 *  before stopping (so you can "jump" forward up to 9 at a time).
 * If you type "c", it toggles character mode--in character mode, the
 *  characters from the trace come out one at at time.  So in
 *  character mode, "9" would get you 9 characters.
 * Typing "q" ends catseq.
 *
 * So the idea is to work your way forward with "9" until you're right
 *  near to the problem.  Then "c" and spaces until you just see the
 *  incorrect event.  Then "q", and now you can examine the trace
 *  file if needed to see exactly what sequence is involved.
 */
#include <stdlib.h>
#include <termios.h>
#include <unistd.h>
#include <stdio.h>
#include <ctype.h>

static FILE *fp, *trcf = NULL;
static unsigned int pos = 0;
static struct termios told;

/*
 * done()
 *	Report final position, restore TTY, and exit
 */
static void
done(void)
{
    tcsetattr(1, TCSANOW, &told);
    fprintf(stderr, "\nFinished at position %u\n", pos);
    exit(0);
}

/*
 * nextc()
 *	Get next char
 *
 * Also handles file position book keeping, and optional logging of
 *  the input stream.
 */
static int
nextc(void)
{
    int x;

    x = fgetc(fp);
    if (x == EOF) {
	done();
    }
    pos += 1;
    if (trcf) {
	fputc(x, trcf);
    }
    return(x);
}

int
main(int argc, char **argv)
{
    char c;
    int x, bychars = 0, nout = 0, oldnout = 1;
    struct termios tnew;

    /* Access file to display */
    if ((argc < 2) || (argc > 3)) {
	fprintf(stderr, "Usage is: %s <file> [<trace-file>]\n",
	    argv[0], argv[1]);
	exit(1);
    }
    fp = fopen(argv[1], "r");
    if (!fp) {
	perror(argv[1]);
	exit(1);
    }
    if (argc == 3) {
	trcf = fopen(argv[2], "w");
	if (!trcf) {
	    perror(argv[2]);
	    exit(1);
	}
    }

    /* Get TTY into single char mode */
    tcgetattr(1, &told);
    tnew = told;
    tnew.c_lflag &= ~(ICANON|ECHO);
    tnew.c_oflag &= ~(ONLCR | OCRNL | OPOST);
    tnew.c_cc[VMIN] = 1;
    tnew.c_cc[VTIME] = 0;
    tcsetattr(1, TCSANOW, &tnew);

    /* Feed bytes */
    for (;;) {
	/* Stop for keyboard input at required interval */
	if (--nout <= 0) {
	    (void)read(0, &c, 1);

	    /* Bail out? */
	    if (c == 'q') {
		done();

	    /* Toggle "by char" mode? */
	    } else if (c == 'c') {
		bychars = !bychars;
		oldnout = nout = 1;

	    /* Get a count of steps */
	    } else if (isdigit(c)) {
		oldnout = nout = c - '0';

	    /*
	     * Any other key, step for the same number as
	     *  last time.
	     */
	    } else {
		nout = oldnout;
	    }
	}

	/* Output the next unit--a char or through an escape sequence */
	if (bychars) {
	    c = nextc();
	    write(1, &c, 1);

	} else {
	    /* Walk into next escape sequence */
	    do {
		c = nextc();
		write(1, &c, 1);
	    } while (c != 27);

	    /* Now walk through the sequence */
	    do {
		c = nextc();
		write(1, &c, 1);
	    } while ((c == ';') || isdigit(c) || (c == '['));
	}
    }
}
