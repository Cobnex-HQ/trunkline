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
#include <libproc.h>
#include <sys/proc.h>
extern char **environ;

static int inheritedTerminalSetting(const char *entry) {
    const char *keys[] = { "TERM=", "COLORTERM=", "TERM_PROGRAM=", "TERM_PROGRAM_VERSION=",
        "NO_COLOR=", "FORCE_COLOR=", "CLICOLOR=", "CLICOLOR_FORCE=", "CI=", "COLUMNS=", "LINES=" };
    for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) {
        if (strncmp(entry, keys[i], strlen(keys[i])) == 0) return 1;
    }
    return 0;
}

pid_t MPStartTerminal(const char *directory, const char *launcherPath, int *masterFD) {
    int master = -1, slave = -1;
    char name[1024];
    struct winsize size = { .ws_row = 30, .ws_col = 80 };
    if (openpty(&master, &slave, name, NULL, &size) < 0) return -1;
    fcntl(master, F_SETFD, FD_CLOEXEC);
    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attributes;
    posix_spawn_file_actions_init(&actions);
    posix_spawnattr_init(&attributes);
    // The launcher explicitly acquires this slave as its controlling terminal.
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
    if (!environment) {
        posix_spawn_file_actions_destroy(&actions);
        posix_spawnattr_destroy(&attributes);
        close(master); close(slave); return -1;
    }
    size_t index = 0;
    for (size_t i = 0; i < count; i++) {
        if (!inheritedTerminalSetting(environ[i])) environment[index++] = environ[i];
    }
    environment[index++] = "TERM=xterm-256color";
    environment[index++] = "COLORTERM=truecolor";
    environment[index++] = "TERM_PROGRAM=Trunkline";
    char *arguments[] = { (char *)launcherPath, NULL };
    pid_t pid = -1;
    int error = posix_spawn(&pid, launcherPath, &actions, &attributes, arguments, environment);
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

int MPSignalTerminalMembers(pid_t sessionLeader, int signalNumber) {
    if (sessionLeader <= 1 || sessionLeader == getsid(0)) { errno = EINVAL; return -1; }
    int bytes = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (bytes <= 0) return -1;
    bytes += 1024 * (int)sizeof(pid_t);
    pid_t *pids = calloc(1, (size_t)bytes);
    if (!pids) return -1;
    int used = proc_listpids(PROC_ALL_PIDS, 0, pids, bytes);
    if (used <= 0 || used >= bytes) { free(pids); return -1; }
    int remaining = 0;
    for (int i = 0; i < used / (int)sizeof(pid_t); i++) {
        pid_t candidate = pids[i];
        if (candidate <= 1 || getsid(candidate) != sessionLeader) continue;
        struct proc_bsdinfo info;
        int size = proc_pidinfo(candidate, PROC_PIDTBSDINFO, 0, &info, sizeof(info));
        if (size == sizeof(info) && info.pbi_status == SZOMB) continue;
        if (candidate != sessionLeader) remaining++;
        if (signalNumber != 0 && getsid(candidate) == sessionLeader) kill(candidate, signalNumber);
    }
    free(pids);
    return remaining;
}
