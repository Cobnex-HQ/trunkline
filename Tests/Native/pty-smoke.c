#include "TerminalPTY.h"
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>
#include <poll.h>
int main(void) {
    int fd = -1; pid_t pid = MPStartTerminal("/private/tmp", &fd);
    if (pid < 0) { perror("PTY spawn"); return 1; }
    MPResizeTerminal(fd, 100, 40);
    // No user environment or prompt output is printed by this test.
    const char *command = "printf '__MACPHONE_%s__\\n' PTY_OK; stty size; exit\r";
    write(fd, command, strlen(command));
    char output[65536] = {0}; size_t used = 0;
    for (int i = 0; i < 100; i++) {
        struct pollfd p = { .fd=fd, .events=POLLIN };
        poll(&p, 1, 100);
        ssize_t n = read(fd, output + used, sizeof(output) - used - 1);
        if (n > 0) used += (size_t)n;
        if (strstr(output, "__MACPHONE_PTY_OK__") && strstr(output, "40 100")) {
            kill(-pid, SIGTERM); close(fd); waitpid(pid, NULL, 0);
            puts("PASS: interactive PTY, shell input/output, and 100x40 resize"); return 0;
        }
        if (used >= sizeof(output) - 1) break;
    }
    kill(-pid, SIGKILL); close(fd); waitpid(pid, NULL, 0);
    fputs("FAIL: interactive terminal or resize did not respond\n", stderr); return 1;
}
