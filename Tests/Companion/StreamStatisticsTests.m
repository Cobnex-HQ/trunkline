#import <XCTest/XCTest.h>
#import <QuartzCore/QuartzCore.h>
#import "StreamManager.h"
#import "VideoDecoderRenderer.h"

// Use the production formatter and substitute only the connection's counters.
// No stream is started and no real host or credentials are accessed.
@interface FixtureStatisticsConnection : Connection
@property(nonatomic) video_stats_t sample;
@property(nonatomic) BOOL available;
@end
@implementation FixtureStatisticsConnection
- (BOOL)getVideoStats:(video_stats_t *)stats { *stats = self.sample; return self.available; }
- (NSString *)getActiveCodecName { return @"HEVC"; }
@end

@interface StreamStatisticsTests : XCTestCase
@end
@implementation StreamStatisticsTests
- (void)testUnsupportedVideoCodecRequestsRecoveryWithoutTerminatingTheApp {
    VideoDecoderRenderer *renderer = [[VideoDecoderRenderer alloc] initWithView:[UIView new]
        callbacks:nil streamAspectRatio:16.0f / 9.0f useFramePacing:NO];
    [renderer setupWithVideoFormat:0 width:1920 height:1080 frameRate:60];
    DECODE_UNIT unit = {0}; unit.frameType = FRAME_TYPE_IDR;
    // Picture buffers transfer ownership to the decoder, including on error.
    unsigned char *picture = calloc(1, 8);
    XCTAssertEqual([renderer submitDecodeBuffer:picture length:8 bufferType:BUFFER_TYPE_PICDATA decodeUnit:&unit], DR_NEED_IDR);
}
- (StreamManager *)managerWithConnection:(FixtureStatisticsConnection *)connection host:(NSString *)host {
    StreamConfiguration *config = [StreamConfiguration new];
    config.width = 1920; config.height = 1080; config.host = host;
    StreamManager *manager = [[StreamManager alloc] initWithConfig:config renderView:nil connectionCallbacks:nil];
    [manager setValue:connection forKey:@"connection"];
    return manager;
}
- (video_stats_t)recentSample {
    CFTimeInterval end = CACurrentMediaTime() - 0.1;
    return (video_stats_t){.startTime = end - 2, .endTime = end,
        .totalFrames = 120, .receivedFrames = 114, .networkDroppedFrames = 6,
        .totalHostProcessingLatency = 800, .framesWithHostProcessingLatency = 20,
        .minHostProcessingLatency = 20, .maxHostProcessingLatency = 70};
}
- (void)testStatisticsReportReceivedFramesAndFractionLostRatherThanLossPerSecond {
    FixtureStatisticsConnection *connection = [FixtureStatisticsConnection new];
    connection.available = YES; connection.sample = [self recentSample];
    NSString *text = [[self managerWithConnection:connection host:@"192.0.2.1"] getStatsOverlayText];
    XCTAssertTrue([text containsString:@"57.00 fps"], @"Received FPS must exclude the six lost frames: %@", text);
    XCTAssertTrue([text containsString:@"5.00%"], @"Six losses out of 120 expected frames is 5%%, not 3%%: %@", text);
    XCTAssertTrue([text containsString:@"4.0 ms"], @"Host samples are tenths of a millisecond: %@", text);
    XCTAssertFalse([text containsString:@"Average network latency"], @"Transport RTT is not glass-to-glass or one-way network latency");
}
- (void)testMissingAndInvalidSamplesDoNotShowInventedRates {
    FixtureStatisticsConnection *connection = [FixtureStatisticsConnection new];
    StreamManager *manager = [self managerWithConnection:connection host:@"192.0.2.1"];
    XCTAssertNil([manager getStatsOverlayText]);
    connection.available = YES;
    video_stats_t sample = [self recentSample]; sample.endTime = sample.startTime;
    connection.sample = sample; XCTAssertNil([manager getStatsOverlayText]);
    sample = [self recentSample]; sample.startTime = NAN;
    connection.sample = sample; XCTAssertNil([manager getStatsOverlayText]);
    sample = [self recentSample]; sample.totalFrames = 0;
    connection.sample = sample; XCTAssertNil([manager getStatsOverlayText]);
    sample = [self recentSample]; sample.networkDroppedFrames = -1;
    connection.sample = sample; XCTAssertNil([manager getStatsOverlayText]);
}
- (void)testStalledStreamDoesNotKeepDisplayingTheLastHealthyFrameRate {
    FixtureStatisticsConnection *connection = [FixtureStatisticsConnection new];
    connection.available = YES;
    video_stats_t sample = [self recentSample]; sample.startTime -= 10; sample.endTime -= 10;
    connection.sample = sample;
    NSString *text = [[self managerWithConnection:connection host:@"192.0.2.1"] getStatsOverlayText];
    XCTAssertEqualObjects(text, @"No recent video");
}
- (void)testLoopbackTransportLatencyIsNotPresentedAsTheRemoteMacNetworkLatency {
    FixtureStatisticsConnection *connection = [FixtureStatisticsConnection new];
    connection.available = YES; connection.sample = [self recentSample];
    for (NSString *host in @[@"127.0.0.1", @"127.0.0.1:47989", @"[::1]:47989", @"localhost:47989"]) {
        NSString *text = [[self managerWithConnection:connection host:host] getStatsOverlayText];
        XCTAssertTrue([text containsString:@"Local transport RTT"], @"Away proxy RTT must be explicitly scoped: %@", text);
    }
}
@end
