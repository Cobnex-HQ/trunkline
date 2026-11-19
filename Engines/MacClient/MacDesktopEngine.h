#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface MacDesktopEngine : NSObject
@property(nonatomic, readonly) AVSampleBufferDisplayLayer *displayLayer;
@property(nonatomic, readonly) uint64_t submittedVideoFrames;
@property(nonatomic, readonly) NSString *pairingToken;
@property(nonatomic, copy, nullable) void (^pairingCode)(NSString *pin);
@property(nonatomic, copy, nullable) void (^paired)(NSData *certificate);
@property(nonatomic, copy, nullable) void (^stateChanged)(NSString *state, NSString * _Nullable error);
- (void)startHost:(NSString *)host certificate:(nullable NSData *)certificate width:(int)width height:(int)height fps:(int)fps bitrate:(int)bitrate away:(BOOL)away;
- (void)stop;
+ (void)finishStopping:(void (^)(void))completion NS_SWIFT_DISABLE_ASYNC;
- (void)moveX:(double)x y:(double)y;
- (void)button:(int)button down:(BOOL)down;
- (void)key:(unsigned short)key down:(BOOL)down modifiers:(unsigned char)modifiers;
- (void)scrollX:(short)x y:(short)y;
@end
NS_ASSUME_NONNULL_END
