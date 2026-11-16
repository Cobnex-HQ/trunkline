#import <Foundation/Foundation.h>

/// Local teardown only. Remote button releases belong to the normal touch or
/// stream-disconnect path, not to late object destruction.
@protocol TrunklineTouchInput <NSObject>
- (void)cancelPendingInput;
@end
