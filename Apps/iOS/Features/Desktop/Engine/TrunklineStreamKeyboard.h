#import "StreamView.h"

/// Trunkline's native keyboard controls and ordered transport boundary.
@interface StreamView (TrunklineKeyboard)
- (void)toggleSoftwareKeyboard;
- (void)emitKeyboardKey:(unsigned short)key action:(unsigned char)action modifiers:(unsigned char)modifiers flags:(unsigned char)flags;
- (void)emitKeyboardText:(NSString *)text;
@end
