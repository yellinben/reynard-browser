#import "RNRMockHostConnection.h"

@interface RNRMockHostConnection ()

@property (nonatomic, readwrite) NSUInteger negotiationCount;
@property (nonatomic, readwrite) NSUInteger openCount;
@property (nonatomic, readwrite) NSUInteger closeCount;
@property (nonatomic, readwrite) BOOL invalidateCalled;
@property (nonatomic, readwrite) RNRProtocolVersion receivedMinimumVersion;
@property (nonatomic, readwrite) RNRProtocolVersion receivedMaximumVersion;
@property (nonatomic, strong, readwrite, nullable) RNROpenSessionRequest *receivedOpenRequest;
@property (nonatomic, strong, readwrite, nullable) RNRSessionIdentifier *receivedCloseIdentifier;

@end

@implementation RNRMockHostConnection

- (instancetype)init {
    self = [super init];
    if (self) {
        _negotiatedVersion = RNRProtocolVersionCurrent;
        _openSessionIdentifier = [[RNRSessionIdentifier alloc] init];
    }
    return self;
}

- (void)negotiateProtocolVersionWithClientMinimumVersion:(RNRProtocolVersion)minimumVersion
                                     clientMaximumVersion:(RNRProtocolVersion)maximumVersion
                                               completion:(void (^)(RNRProtocolVersion negotiatedVersion,
                                                                    NSError * _Nullable error))completion {
    self.negotiationCount += 1;
    self.receivedMinimumVersion = minimumVersion;
    self.receivedMaximumVersion = maximumVersion;
    completion(self.negotiatedVersion, self.negotiationError);
}

- (void)openSessionWithRequest:(RNROpenSessionRequest *)request
                    completion:(void (^)(RNRSessionIdentifier * _Nullable sessionIdentifier,
                                         NSError * _Nullable error))completion {
    self.openCount += 1;
    self.receivedOpenRequest = request;
    completion(self.openSessionIdentifier, self.openError);
}

- (void)closeSessionWithIdentifier:(RNRSessionIdentifier *)sessionIdentifier
                        completion:(void (^)(NSError * _Nullable error))completion {
    self.closeCount += 1;
    self.receivedCloseIdentifier = sessionIdentifier;
    completion(self.closeError);
}

- (void)invalidate {
    self.invalidateCalled = YES;
}

- (void)simulateHostClosureForSessionIdentifier:(RNRSessionIdentifier *)sessionIdentifier
                                          error:(NSError *)error {
    [self.delegate hostServiceDidCloseSessionWithIdentifier:sessionIdentifier error:error];
}

- (void)simulateInvalidationWithError:(NSError *)error {
    [self.delegate hostConnection:self didInvalidateWithError:error];
}

@end
