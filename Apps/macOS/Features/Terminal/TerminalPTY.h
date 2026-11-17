#ifndef MACPHONE_TERMINAL_PTY_H
#define MACPHONE_TERMINAL_PTY_H
#include <sys/types.h>
pid_t MPStartTerminal(const char *directory, int *masterFD);
int MPResizeTerminal(int masterFD, unsigned short columns, unsigned short rows);
/* Signal only live members of this terminal's POSIX session. Excludes the
 * session leader from the returned count. The caller must not reap the leader
 * until cleanup completes, preventing its session ID from being reused. */
int MPSignalTerminalMembers(pid_t sessionLeader, int signalNumber);
#endif
