#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>
#include <stdio.h>

extern char **environ;

// Spawned into a new POSIX session with the PTY slave on stdin/out/err.
// Opening that slave alone does not acquire a controlling terminal on macOS.
// Keep this setup in a separate process, outside the multithreaded AppKit host.
int main(void) {
    if (ioctl(STDIN_FILENO, TIOCSCTTY, 0) < 0 ||
        tcsetpgrp(STDIN_FILENO, getpgrp()) < 0) {
        perror("Trunkline could not initialize the terminal");
        return 126;
    }
    char *arguments[] = { "/bin/zsh", "-l", NULL };
    execve(arguments[0], arguments, environ);
    perror("Trunkline could not start the shell");
    return 127;
}
