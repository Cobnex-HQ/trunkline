#import <XCTest/XCTest.h>
#import "TrunklineExternalVideo.h"

@interface RecordingExternalLayer : AVSampleBufferDisplayLayer
@property(nonatomic) NSInteger frames;
@property(nonatomic) NSInteger clears;
@property(nonatomic) BOOL accepting;
@end
@implementation RecordingExternalLayer
- (BOOL)isReadyForMoreMediaData { return self.accepting; }
- (void)enqueueSampleBuffer:(CMSampleBufferRef)sample { self.frames += 1; }
- (void)flushAndRemoveImage { self.clears += 1; }
@end

@interface ExternalVideoTests : XCTestCase
@end
@implementation ExternalVideoTests
- (void)testOnlySelectedStreamCanFeedDisplayAndDetachClearsImage {
    TrunklineExternalVideo *output = [TrunklineExternalVideo new];
    UIView *root = [UIView new], *source = [UIView new], *other = [UIView new];
    [root addSubview:source];
    RecordingExternalLayer *layer = [RecordingExternalLayer new]; layer.accepting = YES;
    XCTAssertTrue([output attachLayer:layer sourceView:root owner:@"first"]);
    XCTAssertFalse([output attachLayer:[RecordingExternalLayer new] sourceView:other owner:@"second"]);
    CMSampleBufferRef sample = NULL;
    CMSampleBufferCreate(kCFAllocatorDefault, NULL, false, NULL, NULL, NULL, 0, 0, NULL, 0, NULL, &sample);
    [output submit:sample fromView:other isKeyframe:YES];
    XCTAssertEqual(layer.frames, 0);
    [output submit:sample fromView:source isKeyframe:YES];
    XCTAssertEqual(layer.frames, 1);
    [output detachOwner:@"second"];
    [output submit:sample fromView:source isKeyframe:YES];
    XCTAssertEqual(layer.frames, 2);
    [output detachOwner:@"first"];
    XCTAssertGreaterThan(layer.clears, 0);
    [output submit:sample fromView:source isKeyframe:YES];
    XCTAssertEqual(layer.frames, 2);
    CFRelease(sample);
}
- (void)testNewOutputWaitsForKeyframeAndRecoversAfterBackpressure {
    TrunklineExternalVideo *output = [TrunklineExternalVideo new];
    UIView *source = [UIView new];
    RecordingExternalLayer *layer = [RecordingExternalLayer new]; layer.accepting = YES;
    [output attachLayer:layer sourceView:source owner:@"owner"];
    CMSampleBufferRef sample = NULL;
    CMSampleBufferCreate(kCFAllocatorDefault, NULL, false, NULL, NULL, NULL, 0, 0, NULL, 0, NULL, &sample);
    XCTAssertTrue([output submit:sample fromView:source isKeyframe:NO]);
    XCTAssertFalse([output submit:sample fromView:source isKeyframe:NO]);
    XCTAssertEqual(layer.frames, 0);
    [output submit:sample fromView:source isKeyframe:YES];
    XCTAssertEqual(layer.frames, 1);
    layer.accepting = NO;
    [output submit:sample fromView:source isKeyframe:NO];
    layer.accepting = YES;
    [output submit:sample fromView:source isKeyframe:NO];
    XCTAssertEqual(layer.frames, 1);
    [output submit:sample fromView:source isKeyframe:YES];
    XCTAssertEqual(layer.frames, 2);
    CFRelease(sample);
}
@end
