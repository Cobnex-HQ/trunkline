// Adapted from Trunkline’s Moonlight iOS bridge for macOS.
// Bind the pending Sunshine request to a random token carried separately in
// the authenticated companion channel, without changing the vendor sources.
@interface TrunklinePairingHttpManager : HttpManager
@property(nonatomic, copy) NSString *pairingName;
- (void)cancelPendingRequests;
@end
@implementation TrunklinePairingHttpManager {
    NSMutableSet<NSURLSession *> *_sessions;
    BOOL _stopped;
}
- (void)cancelPendingRequests {
    NSArray<NSURLSession *> *sessions;
    @synchronized (self) { _stopped = YES; sessions = _sessions.allObjects; }
    for (NSURLSession *session in sessions) [session invalidateAndCancel];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler {
    // A paired endpoint must never redirect authentication to another server.
    completionHandler(nil);
}
// Preserve the pinned engine's request/fallback semantics and inherited TLS
// challenge handler, while owning session lifetime so Cancel stops network I/O.
- (void)executeRequestSynchronously:(HttpRequest *)request {
    NSURLSession *session;
    NSURLSessionDataTask *task;
    __block NSData *responseData;
    __block NSError *responseError;
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    @synchronized (self) {
        if (_stopped) {
            request.response.statusCode = NSURLErrorCancelled;
            request.response.statusMessage = @"Desktop request cancelled.";
            return;
        }
        if (!request.request) {
            request.response.statusCode = EHOSTDOWN;
            request.response.statusMessage = @"Trunkline Desktop is unreachable.";
            return;
        }
        session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration delegate:self delegateQueue:nil];
        task = [session dataTaskWithRequest:request.request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            responseData = data; responseError = error;
            dispatch_semaphore_signal(finished);
        }];
        if (!_sessions) _sessions = [NSMutableSet new];
        [_sessions addObject:session];
    }
    [task resume];
    dispatch_semaphore_wait(finished, DISPATCH_TIME_FOREVER);
    [session invalidateAndCancel];
    @synchronized (self) {
        [_sessions removeObject:session];
        if (_stopped) {
            request.response.statusCode = NSURLErrorCancelled;
            request.response.statusMessage = @"Desktop request cancelled.";
            return;
        }
    }
    if (!responseError) {
        NSString *xml = responseData ? [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] : nil;
        if (xml) {
            xml = [xml stringByReplacingOccurrencesOfString:@"UTF-16" withString:@"UTF-8" options:NSCaseInsensitiveSearch range:NSMakeRange(0, xml.length)];
            responseData = [xml dataUsingEncoding:NSUTF8StringEncoding];
        }
        [request.response populateWithData:responseData];
    } else {
        request.response.statusCode = responseError.code;
        request.response.statusMessage = responseError.localizedDescription;
    }
    // Fallback is supplied only by the engine's server-information request.
    // Certificate failures on app listing/launch never downgrade to HTTP.
    if (request.fallbackRequest && ((!responseError && request.response.statusCode == request.fallbackError) ||
                                   responseError.code == NSURLErrorServerCertificateUntrusted)) {
        request.request = request.fallbackRequest;
        request.fallbackRequest = nil; request.fallbackError = 0;
        [self executeRequestSynchronously:request];
    }
}
- (NSURLRequest *)newPairRequest:(NSData *)salt clientCert:(NSData *)clientCert {
    NSMutableURLRequest *request = [[super newPairRequest:salt clientCert:clientCert] mutableCopy];
    NSURLComponents *url = [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
    for (NSURLQueryItem *item in url.queryItems) {
        [items addObject:[item.name isEqualToString:@"devicename"] ? [NSURLQueryItem queryItemWithName:@"devicename" value:self.pairingName] : item];
    }
    url.queryItems = items; request.URL = url.URL;
    return request;
}
@end
