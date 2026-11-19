#import <XCTest/XCTest.h>
#import "StreamManager.h"
#import "StreamConfiguration.h"

extern BOOL TrunklineDesktopStreamAvailable(void);

@interface DelayedStopConnection : NSObject
@property(nonatomic, copy) dispatch_block_t completion;
@end
@implementation DelayedStopConnection
- (void)terminateWithCompletion:(dispatch_block_t)completion { self.completion = completion; }
@end

@interface StreamOwnershipTests : XCTestCase
@end
@implementation StreamOwnershipTests
- (void)testRepeatedStopKeepsLeaseUntilNativeShutdownCompletes {
    StreamManager *manager = [[StreamManager alloc] initWithConfig:[StreamConfiguration new] renderView:[UIView new] connectionCallbacks:nil];
    DelayedStopConnection *connection = [DelayedStopConnection new];
    [manager setValue:connection forKey:@"connection"];
    [manager stopStream];
    [manager stopStream];
    XCTestExpectation *check = [self expectationWithDescription:@"Shutdown completion releases the lease"];
    dispatch_async(dispatch_get_main_queue(), ^{
        XCTAssertFalse(TrunklineDesktopStreamAvailable());
        XCTAssertNotNil(connection.completion);
        connection.completion();
        XCTAssertTrue(TrunklineDesktopStreamAvailable());
        [check fulfill];
    });
    [self waitForExpectations:@[check] timeout:2];
}
- (void)testSecondWindowCannotReleaseTheFirstDesktopLease {
    XCTAssertTrue(TrunklineDesktopStreamAvailable());
    StreamManager *first = [[StreamManager alloc] initWithConfig:[StreamConfiguration new] renderView:[UIView new] connectionCallbacks:nil];
    StreamManager *second = [[StreamManager alloc] initWithConfig:[StreamConfiguration new] renderView:[UIView new] connectionCallbacks:nil];
    XCTAssertFalse(TrunklineDesktopStreamAvailable());
    [second stopStream];
    XCTestExpectation *check = [self expectationWithDescription:@"Only the owning stream can release the engine"];
    dispatch_async(dispatch_get_main_queue(), ^{
        XCTAssertFalse(TrunklineDesktopStreamAvailable());
        [first stopStream];
        dispatch_async(dispatch_get_main_queue(), ^{
            XCTAssertTrue(TrunklineDesktopStreamAvailable());
            [check fulfill];
        });
    });
    [self waitForExpectations:@[check] timeout:2];
}
@end
