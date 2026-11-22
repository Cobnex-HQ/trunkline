#import <UIKit/UIKit.h>
#import "StreamConfiguration.h"

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT BOOL TrunklineDesktopStreamAvailable(void);
FOUNDATION_EXPORT NSDictionary<NSString *, NSNumber *> * _Nullable TrunklineDesktopNetworkSample(void);
@interface TrunklineStream : NSObject
@property(nonatomic, readonly, copy) NSString *pairingToken;
@property(nonatomic, copy, nullable) void (^pairingCode)(NSString *);
@property(nonatomic, copy, nullable) void (^paired)(NSData *);
@property(nonatomic, copy, nullable) void (^failed)(NSString *);
- (void)loadHost:(NSString *)address certificate:(nullable NSData *)certificate
     completion:(void (^)(NSArray<NSDictionary<NSString *, NSString *> *> * _Nullable apps, NSString * _Nullable error, BOOL retryable))completion NS_SWIFT_DISABLE_ASYNC;
- (void)pair;
- (nullable StreamConfiguration *)configurationForApp:(NSString *)appID title:(NSString *)title
    width:(int)width height:(int)height fps:(int)fps bitrate:(int)bitrate directTouch:(BOOL)directTouch framePacing:(BOOL)framePacing stats:(BOOL)stats;
- (UIViewController *)streamControllerWithConfig:(StreamConfiguration *)config close:(void (^)(void))close workspaceAction:(void (^)(NSString *))workspaceAction;
- (void)showKeyboardInController:(UIViewController *)controller;
- (void)changeZoomInController:(UIViewController *)controller factor:(CGFloat)factor;
- (void)updateDisplayInController:(UIViewController *)controller width:(int)width height:(int)height;
- (void)resetZoomInController:(UIViewController *)controller;
- (void)sendKey:(unsigned short)key modifiers:(unsigned char)modifiers;
- (void)sendText:(NSString *)text;
- (void)cancel;
@end

NS_ASSUME_NONNULL_END
