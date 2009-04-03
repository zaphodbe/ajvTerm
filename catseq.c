/*
 * catseq.c
 *	Output escape sequences a few at a time
 */
#include <stdlib.h>
#include <termios.h>
#include <unistd.h>
#include <stdio.h>
#include <ctype.h>

static FILE *fp, *trcf = NULL;
static int done = 0;
static unsigned int pos = 0;

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
	done = 1;
    } else {
	pos += 1;
	if (trcf) {
	    fputc(x, trcf);
	}
    }
    return(x);
}

int
main(int argc, char **argv)
{
    struct termios told, tnew;
    char c;
    int x, nchar = 0, step, bychars = 0;

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
    tnew.c_cc[VMIN] = 1;
    tnew.c_cc[VTIME] = 0;
    tcsetattr(1, TCSANOW, &tnew);

    /* Feed bytes */
    do {
	x = nextc();
	if (x == EOF) {
	    break;
	}
	c = x;

	/*
	 * Things flow through until we hit an escape sequence,
	 *  or we're in char-at-a-time mode.
	 */
	write(1, &c, 1);
	if (!bychars && (c != 27)) {
	    continue;
	}

	/* Copy until the end of this sequence */
	for (;;) {
	    x = nextc();
	    if (x == EOF) {
		break;
	    }
	    c = x;
	    write(1, &c, 1);

	    /*
	     * We interact with the keyboard on each char if we're
	     *  in "by chars" mode, otherwise at the end of the
	     *  current escape sequence.
	     */
	    if (bychars) {
		step = 1;
	    } else  {
		step = (c != ';') && !isdigit(c) && (c != '[');
	    }

	    /* Time step interact with the keyboard? */
	    if (step) {
		if (nchar) {
		    nchar -= 1;
		} else {
		    (void)read(0, &c, 1);

		    /* Bail out? */
		    if (c == 'q') {
			done = 1;

		    /* Toggle "by char" mode? */
		    } else if (c == 'c') {
			bychars = !bychars;

		    /* Get a count of steps */
		    } else if (isdigit(c)) {
			nchar = c - '0';
		    }
		}
		break;
	    }
	}
    } while (!done);
    tcsetattr(1, TCSANOW, &told);
    fprintf(stderr, "\nFinished at position %u\n", pos);
    return(0);
}