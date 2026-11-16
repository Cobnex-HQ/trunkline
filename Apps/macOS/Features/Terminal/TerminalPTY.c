#include "TerminalPTY.h"
#include <util.h>
#include <spawn.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
extern char **environ;

pid_t MPStartTerminal(const char *directory, int *masterFD) {
    int master = -1, slave = -1;
    char name[1024];
    struct winsize size = { .ws_row = 30, .ws_col = 80 };
    if (openpty(&master, &slave, name, NULL, &size) < 0) return -1;
    fcntl(master, F_SETFD, FD_CLOEXEC);
    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attributes;
    posix_spawn_file_actions_init(&actions);
    posix_spawnattr_init(&attributes);
    // The new session opens its slave after setsid, acquiring a controlling TTY.
    posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETSID | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK);
    sigset_t defaults, mask;
    sigfillset(&defaults); sigemptyset(&mask);
    posix_spawnattr_setsigdefault(&attributes, &defaults);
    posix_spawnattr_setsigmask(&attributes, &mask);
    posix_spawn_file_actions_addclose(&actions, master);
    posix_spawn_file_actions_addclose(&actions, slave);
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, name, O_RDWR, 0);
    posix_spawn_file_actions_adddup2(&actions, STDIN_FILENO, STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, STDIN_FILENO, STDERR_FILENO);
    if (__builtin_available(macOS 26.0, *)) posix_spawn_file_actions_addchdir(&actions, directory);
    else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        posix_spawn_file_actions_addchdir_np(&actions, directory);
#pragma clang diagnostic pop
    }
    size_t count = 0;
    while (environ[count]) count++;
    char **environment = calloc(count + 4, sizeof(char *));
    if (!environment) { close(master); close(slave); return -1; }
    size_t index = 0;
    for (size_t i = 0; i < count; i++) {
        if (strncmp(environ[i], "TERM=", 5) && strncmp(environ[i], "COLORTERM=", 10)) environment[index++] = environ[i];
    }
    environment[index++] = "TERM=xterm-256color";
    environment[index++] = "COLORTERM=truecolor";
    char *arguments[] = { "/bin/zsh", "-l", NULL };
    pid_t pid = -1;
    int error = posix_spawn(&pid, "/bin/zsh", &actions, &attributes, arguments, environment);
    free(environment);
    posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes);
    close(slave);
    if (error) { close(master); errno = error; return -1; }
    fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK);
    *masterFD = master;
    return pid;
}
int MPResizeTerminal(int masterFD, unsigned short columns, unsigned short rows) {
    struct winsize size = { .ws_row = rows, .ws_col = columns };
    return ioctl(masterFD, TIOCSWINSZ, &size);
}
