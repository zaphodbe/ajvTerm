/*
 * catseq.c
 *	Output escape sequences a few at a time
 */
#include <stdlib.h>
#include <termios.h>
#include <unistd.h>
#include <stdio.h>
#include <ctype.h>

int
main(int argc, char **argv)
{
    struct termios told, tnew;
    FILE *fp;
    char c;
    int x, nesc = 0, done = 0;

    /* Access file to display */
    if (argc != 2) {
	fprintf(stderr, "Usage is: %s <file>\n", argv[0], argv[1]);
	exit(1);
    }
    fp = fopen(argv[1], "r");
    if (!fp) {
	perror(argv[1]);
	exit(1);
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
	x = fgetc(fp);
	if (x == EOF) {
	    done = 1;
	    break;
	}
	c = x;

	/* Everything except escape sequences goes straight through */
	putchar(c);
	if (c != 27) {
	    continue;
	}

	/* Copy until the end of this escape sequence */
	for (;;) {
	    x = fgetc(fp);
	    if (x == EOF) {
		done = 1;
		break;
	    }
	    c = x;
	    putchar(c);
	    if ((c != ';') && !isdigit(c)) {
		if (nesc) {
		    nesc -= 1;
		} else {
		    (void)read(0, &c, 1);
		    if (c == 'q') {
			done = 1;
		    }
		    if (isdigit(c)) {
			nesc = c - '0';
		    }
		}
		break;
	    }
	}
    } while (!done);
    tcsetattr(1, TCSANOW, &told);
    putchar('\n');
    return(0);
}
