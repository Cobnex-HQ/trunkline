/**
 * Launch the bundled Sunshine runtime and stop it if the owning Mac app exits.
 * This supervisor owns one process group; it does not capture or stream media.
 */
#include <errno.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;
static volatile sig_atomic_t stopping = 0;
static void request_stop(int signal_number) { (void)signal_number; stopping = 1; }
static void pause_briefly(void) {
    struct timespec delay = {.tv_sec = 0, .tv_nsec = 100000000};
    nanosleep(&delay, NULL);
}
static void stop_group(pid_t child) {
    int status = 0;
    int reaped = 0;
    kill(-child, SIGTERM);
    for (int attempt = 0; attempt < 10; attempt++) {
        pid_t result = waitpid(child, &status, WNOHANG);
        if (result == child || (result < 0 && errno == ECHILD)) { reaped = 1; break; }
        pause_briefly();
    }
    // Also stop descendants if the main child has exited before them.
    kill(-child, SIGKILL);
    if (!reaped) while (waitpid(child, &status, 0) < 0 && errno == EINTR) {}
}
int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "Usage: TrunklineDesktopSupervisor executable [arguments...]\n"); return 64; }
    const pid_t owner = getppid();
    if (owner <= 1) return 70;
    struct sigaction action;
    memset(&action, 0, sizeof(action)); action.sa_handler = request_stop;
    sigemptyset(&action.sa_mask);
    sigaction(SIGTERM, &action, NULL); sigaction(SIGINT, &action, NULL); sigaction(SIGHUP, &action, NULL);
    posix_spawnattr_t attributes;
    int error = posix_spawnattr_init(&attributes);
    if (error) return 71;
    sigset_t mask, defaults;
    sigemptyset(&mask); sigemptyset(&defaults);
    sigaddset(&defaults, SIGTERM); sigaddset(&defaults, SIGINT); sigaddset(&defaults, SIGHUP);
    posix_spawnattr_setsigmask(&attributes, &mask);
    posix_spawnattr_setsigdefault(&attributes, &defaults);
    posix_spawnattr_setpgroup(&attributes, 0);
    posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK);
    pid_t child = 0;
    error = posix_spawn(&child, argv[1], NULL, &attributes, argv + 1, environ);
    posix_spawnattr_destroy(&attributes);
    if (error) { fprintf(stderr, "Sunshine launch failed: %s\n", strerror(error)); return 71; }
    for (;;) {
        if (stopping || getppid() != owner) { stop_group(child); return 0; }
        int status = 0;
        pid_t result = waitpid(child, &status, WNOHANG);
        if (result == child) {
            kill(-child, SIGTERM);
            return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
        }
        if (result < 0 && errno != EINTR) { stop_group(child); return 71; }
        pause_briefly();
    }
}
