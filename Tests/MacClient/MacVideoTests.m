#import <XCTest/XCTest.h>
#import <VideoToolbox/VideoToolbox.h>
#import "MacDesktopEngine.h"
#import <Limelight.h>

@interface MacDesktopEngine (Testing)
- (int)submit:(PDECODE_UNIT)unit;
@end
@interface MacVideoTests : XCTestCase
@end

static void encoded(void *ref, void *source, OSStatus status, VTEncodeInfoFlags flags, CMSampleBufferRef sample) {
    if (status || !sample) return;
    NSMutableData *annex = (__bridge NSMutableData *)ref;
    CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sample);
    const uint8_t prefix[] = {0,0,0,1};
    for (int i=0;i<2;i++) {
        const uint8_t *bytes; size_t size;
        if (CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format,i,&bytes,&size,NULL,NULL)) return;
        [annex appendBytes:prefix length:4]; [annex appendBytes:bytes length:size];
    }
    CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sample);
    size_t size = CMBlockBufferGetDataLength(block);
    NSMutableData *data = [NSMutableData dataWithLength:size];
    CMBlockBufferCopyDataBytes(block,0,size,data.mutableBytes);
    const uint8_t *bytes = data.bytes;
    for (size_t offset=0;offset+4<=size;) {
        uint32_t length; memcpy(&length,bytes+offset,4); length=ntohl(length); offset+=4;
        if (!length || length>size-offset) return;
        [annex appendBytes:prefix length:4]; [annex appendBytes:bytes+offset length:length];
        offset+=length;
    }
}
@implementation MacVideoTests
- (void)testMalformedVideoRequestsAKeyframe {
    MacDesktopEngine *engine = [MacDesktopEngine new];
    DECODE_UNIT unit = {0};
    XCTAssertEqual([engine submit:&unit], DR_NEED_IDR);
    unit.fullLength = 9*1024*1024;
    XCTAssertEqual([engine submit:&unit], DR_NEED_IDR);
}
- (void)testRealH264FrameDecodesThroughTheNativeRenderer {
    NSMutableData *annex = [NSMutableData new];
    VTCompressionSessionRef encoder = NULL;
    XCTAssertEqual(VTCompressionSessionCreate(NULL,64,64,kCMVideoCodecType_H264,NULL,NULL,NULL,encoded,(__bridge void *)annex,&encoder), noErr);
    if (!encoder) return;
    VTSessionSetProperty(encoder,kVTCompressionPropertyKey_RealTime,kCFBooleanTrue);
    VTSessionSetProperty(encoder,kVTCompressionPropertyKey_AllowFrameReordering,kCFBooleanFalse);
    CVPixelBufferRef pixel = NULL;
    XCTAssertEqual(CVPixelBufferCreate(NULL,64,64,kCVPixelFormatType_32BGRA,(__bridge CFDictionaryRef)@{(id)kCVPixelBufferIOSurfacePropertiesKey:@{}},&pixel),noErr);
    if (!pixel) { CFRelease(encoder); return; }
    CVPixelBufferLockBaseAddress(pixel,0);
    memset(CVPixelBufferGetBaseAddress(pixel),127,CVPixelBufferGetBytesPerRow(pixel)*64);
    CVPixelBufferUnlockBaseAddress(pixel,0);
    XCTAssertEqual(VTCompressionSessionEncodeFrame(encoder,pixel,CMTimeMake(1,60),CMTimeMake(1,60),NULL,NULL,NULL),noErr);
    VTCompressionSessionCompleteFrames(encoder,kCMTimeInvalid);
    VTCompressionSessionInvalidate(encoder); CFRelease(encoder); CVPixelBufferRelease(pixel);
    XCTAssertGreaterThan(annex.length,0u);
    MacDesktopEngine *engine = [MacDesktopEngine new];
    LENTRY entry = {.data = annex.mutableBytes, .length = (int)annex.length, .bufferType = BUFFER_TYPE_PICDATA};
    DECODE_UNIT unit = {.fullLength = (int)annex.length, .bufferList = &entry, .frameType = FRAME_TYPE_IDR};
    XCTAssertEqual([engine submit:&unit],DR_OK);
    XCTestExpectation *ready = [[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        return engine.displayLayer.readyForDisplay;
    }] object:engine];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[ready] timeout:5],XCTWaiterResultCompleted);
    XCTAssertNotEqual(engine.displayLayer.sampleBufferRenderer.status,AVQueuedSampleBufferRenderingStatusFailed);
}
@end
