#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN
// Main-thread only. The secondary decoder never queues work ahead of playback.
@interface TrunklineExternalVideo : NSObject
+ (instancetype)shared;
- (BOOL)attachLayer:(AVSampleBufferDisplayLayer *)layer sourceView:(UIView *)source owner:(NSString *)owner;
- (void)detachOwner:(NSString *)owner;
- (void)detachLayer:(AVSampleBufferDisplayLayer *)layer;
// Returns YES when the active engine should request a fresh keyframe.
- (BOOL)submit:(CMSampleBufferRef)sample fromView:(UIView *)source isKeyframe:(BOOL)isKeyframe;
@end
NS_ASSUME_NONNULL_END
