/** @file CaptureLifecycleCheck.mm
 * @brief Exercise AVVideo cancellation with inert AVFoundation boundaries; no screen recording.
 */
#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <atomic>
#include <cstdio>

static bool allowOutput = true;
static bool connectionAvailable = true;
static unsigned removedOutputs = 0;
@interface TestCaptureSession: NSObject
- (BOOL)canAddInput:(id)input;
- (void)addInput:(id)input;
- (BOOL)canAddOutput:(id)output;
- (void)addOutput:(id)output;
- (void)removeOutput:(id)output;
- (void)startRunning;
- (void)stopRunning;
@end
@implementation TestCaptureSession
- (BOOL)canAddInput:(id)input { return YES; }
- (void)addInput:(id)input {}
- (BOOL)canAddOutput:(id)output { return allowOutput; }
- (void)addOutput:(id)output {}
- (void)removeOutput:(id)output { ++removedOutputs; }
- (void)startRunning {}
- (void)stopRunning {}
@end
@interface TestScreenInput: NSObject
- (id)initWithDisplayID:(CGDirectDisplayID)display;
- (void)setMinFrameDuration:(CMTime)value;
@end
@implementation TestScreenInput
- (id)initWithDisplayID:(CGDirectDisplayID)display { return [super init]; }
- (void)setMinFrameDuration:(CMTime)value {}
@end
@interface TestVideoOutput: AVCaptureVideoDataOutput {
@public id callbackDelegate; dispatch_queue_t callbackQueue; id fakeConnection;
}
- (void)emitFrame;
@end
static TestVideoOutput *lastOutput;
@implementation TestVideoOutput
- (id)init { self = [super init]; fakeConnection = [NSObject new]; lastOutput = self; return self; }
- (void)setVideoSettings:(NSDictionary *)settings {}
- (AVCaptureConnection *)connectionWithMediaType:(AVMediaType)mediaType { return connectionAvailable ? (AVCaptureConnection *)fakeConnection : nil; }
- (void)setSampleBufferDelegate:(id)delegate queue:(dispatch_queue_t)queue {
  @synchronized(self) {
    callbackDelegate = delegate;
    if (queue) { dispatch_retain(queue); }
    if (callbackQueue) { dispatch_release(callbackQueue); }
    callbackQueue = queue;
  }
}
- (void)emitFrame {
  @synchronized(self) {
    if (!callbackQueue || !callbackDelegate) { return; }
    id target = callbackDelegate;
    id connection = fakeConnection;
    CMSampleBufferRef sample = nullptr;
    if (CMSampleBufferCreateReady(kCFAllocatorDefault, nullptr, nullptr, 0, 0, nullptr, 0, nullptr, &sample) != noErr) { abort(); }
    dispatch_async(callbackQueue, ^{
      [target captureOutput:self didOutputSampleBuffer:sample fromConnection:connection];
      CFRelease(sample);
    });
  }
}
- (void)dealloc {
  if (callbackQueue) { dispatch_release(callbackQueue); }
  [fakeConnection release];
  [super dealloc];
}
@end
#define AVVideo TrunklineCaptureCheckVideo
#define AVCaptureSession TestCaptureSession
#define AVCaptureScreenInput TestScreenInput
#define AVCaptureVideoDataOutput TestVideoOutput
#include "platform/macos/av_video.m"
#undef AVCaptureVideoDataOutput
#undef AVCaptureScreenInput
#undef AVCaptureSession
#undef AVVideo
// Declare the intended lifecycle contract so the baseline reports the missing behavior.
@interface TrunklineCaptureCheckVideo (CancellationContract)
- (void)cancelCapture:(dispatch_semaphore_t)signal;
@end
static bool signalled(dispatch_semaphore_t value, int milliseconds = 2000) {
  return dispatch_semaphore_wait(value, dispatch_time(DISPATCH_TIME_NOW, milliseconds * NSEC_PER_MSEC)) == 0;
}
int main() {
  @autoreleasepool {
    auto *video = [[TrunklineCaptureCheckVideo alloc] initWithDisplay:CGMainDisplayID() frameRate:60];
    if (![video respondsToSelector:@selector(cancelCapture:)]) {
      std::puts("FAIL: capture cannot be cancelled when no new frame arrives"); [video release]; return 1;
    }
    auto stopped = [video capture:^bool(CMSampleBufferRef) { return true; }];
    [video cancelCapture:stopped];
    if (!signalled(stopped) || removedOutputs != 1) { return 2; }
    [video cancelCapture:stopped];
    if (signalled(stopped, 10) || removedOutputs != 1) { return 3; }
    dispatch_release(stopped);

    auto entered = dispatch_semaphore_create(0);
    auto releaseFrame = dispatch_semaphore_create(0);
    auto cancelled = dispatch_semaphore_create(0);
    auto *calls = new std::atomic<unsigned>(0);
    stopped = [video capture:^bool(CMSampleBufferRef) {
      ++*calls; dispatch_semaphore_signal(entered);
      dispatch_semaphore_wait(releaseFrame, DISPATCH_TIME_FOREVER);
      return true;
    }];
    auto *output = [lastOutput retain];
    [output emitFrame];
    if (!signalled(entered)) { return 4; }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      [video cancelCapture:stopped]; dispatch_semaphore_signal(cancelled);
    });
    if (signalled(cancelled, 30)) { return 5; }
    dispatch_semaphore_signal(releaseFrame);
    if (!signalled(cancelled) || !signalled(stopped) || calls->load() != 1) { return 6; }
    [output emitFrame];
    if (output->callbackQueue || output->callbackDelegate || calls->load() != 1) { return 7; }
    [output release]; delete calls;
    dispatch_release(stopped); dispatch_release(entered); dispatch_release(releaseFrame); dispatch_release(cancelled);

    stopped = [video capture:^bool(CMSampleBufferRef) { return false; }];
    [lastOutput emitFrame];
    if (!signalled(stopped) || removedOutputs != 3) { return 8; }
    dispatch_release(stopped);
    allowOutput = false;
    if ([video capture:^bool(CMSampleBufferRef) { return true; }] != nil) { return 9; }
    allowOutput = true; connectionAvailable = false;
    @try {
      if ([video capture:^bool(CMSampleBufferRef) { return true; }] != nil) { std::puts("FAIL: missing video connection returned a completion semaphore that cannot complete"); return 10; }
    } @catch (NSException *exception) {
      std::puts("FAIL: a missing video connection must return failure, not throw"); return 11;
    }
    [video release];
    std::puts("PASS: no-frame cancellation, in-flight drain, exact-once completion, normal stop and output failure; no capture device opened");
  }
}
