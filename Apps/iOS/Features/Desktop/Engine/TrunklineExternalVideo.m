#import "TrunklineExternalVideo.h"

@implementation TrunklineExternalVideo {
    __weak AVSampleBufferDisplayLayer *_layer;
    __weak UIView *_source;
    NSString *_owner;
    BOOL _waitingForKeyframe;
    CFTimeInterval _lastRequest;
}
+ (instancetype)shared {
    static TrunklineExternalVideo *output;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ output = [TrunklineExternalVideo new]; });
    return output;
}
- (BOOL)attachLayer:(AVSampleBufferDisplayLayer *)layer sourceView:(UIView *)source owner:(NSString *)owner {
    NSAssert(NSThread.isMainThread, @"External video is main-thread confined");
    if (_layer && _source && ![_owner isEqualToString:owner]) return NO;
    if (_layer == layer && _source == source && [_owner isEqualToString:owner]) return YES;
    [_layer flushAndRemoveImage];
    _layer = layer; _source = source; _owner = [owner copy];
    _waitingForKeyframe = YES; _lastRequest = -DBL_MAX;
    layer.videoGravity = AVLayerVideoGravityResizeAspect;
    return YES;
}
- (void)detachOwner:(NSString *)owner {
    NSAssert(NSThread.isMainThread, @"External video is main-thread confined");
    if (![_owner isEqualToString:owner]) return;
    [_layer flushAndRemoveImage];
    _layer = nil; _source = nil; _owner = nil;
}
- (void)detachLayer:(AVSampleBufferDisplayLayer *)layer {
    if (_layer == layer && _owner) [self detachOwner:_owner];
}
- (BOOL)submit:(CMSampleBufferRef)sample fromView:(UIView *)source isKeyframe:(BOOL)isKeyframe {
    NSAssert(NSThread.isMainThread, @"External video is main-thread confined");
    AVSampleBufferDisplayLayer *layer = _layer;
    UIView *root = _source;
    if (!layer || !root || ![source isDescendantOfView:root]) return NO;
    if (layer.status == AVQueuedSampleBufferRenderingStatusFailed || !layer.readyForMoreMediaData) {
        [layer flushAndRemoveImage];
        _waitingForKeyframe = YES;
    }
    if (isKeyframe && layer.readyForMoreMediaData) _waitingForKeyframe = NO;
    if (_waitingForKeyframe) {
        CFTimeInterval now = CACurrentMediaTime();
        if (now - _lastRequest < 1) return NO;
        _lastRequest = now;
        return YES;
    }
    // Copy metadata, retaining encoded bytes. Never alter the primary player's sample.
    CMSampleBufferRef copy = NULL;
    if (CMSampleBufferCreateCopy(kCFAllocatorDefault, sample, &copy) != noErr) return NO;
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(copy, YES);
    if (attachments && CFArrayGetCount(attachments)) {
        CFMutableDictionaryRef values = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
        CFDictionarySetValue(values, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
    }
    [layer enqueueSampleBuffer:copy];
    CFRelease(copy);
    return NO;
}
@end
