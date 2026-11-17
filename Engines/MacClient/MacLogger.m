#import "Logger.h"
// Upstream diagnostic messages can contain pairing secrets. Never emit them.
void Log(LogLevel level, NSString *format, ...) {}
void LogTag(LogLevel level, NSString *tag, NSString *format, ...) {}
