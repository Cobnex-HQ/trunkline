#ifndef MACPHONE_TERMINAL_PTY_H
#define MACPHONE_TERMINAL_PTY_H
#include <sys/types.h>
pid_t MPStartTerminal(const char *directory, int *masterFD);
int MPResizeTerminal(int masterFD, unsigned short columns, unsigned short rows);
#endif
