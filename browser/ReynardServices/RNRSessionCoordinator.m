#import "RNRSessionCoordinator.h"

@interface RNRSessionCoordinator ()

@property (nonatomic, strong) id<RNRHostConnection> hostConnection;
@property (nonatomic, strong) NSMutableSet<RNRSessionIdentifier *> *mutableSessionIdentifiers;
@property (nonatomic, readwrite, getter=isReady) BOOL ready;
@property (nonatomic, getter=isInvalidated) BOOL invalidated;

@end


@implementation RNRSessionCoordinator

- (instancetype)initWithHostConnection:(id<RNRHostConnection>)hostConnection {
    self = [super init];
    if (self) {
        _hostConnection = hostConnection;
        _hostConnection.delegate = self;
        _mutableSessionIdentifiers = [NSMutableSet set];
    }
    return self;
}

- (NSSet<RNRSessionIdentifier *> *)activeSessionIdentifiers {
    return [self.mutableSessionIdentifiers copy];
}

- (void)openSessionWithRequest:(RNROpenSessionRequest *)request
                    completion:(RNRSessionCoordinatorOpenCompletion)completion {
    if (self.isInvalidated) {
        completion(nil, [self errorWithCode:RNRProtocolErrorHostUnavailable]);
        return;
    }

    if (self.isReady) {
        [self forwardOpenRequest:request completion:completion];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [self.hostConnection
        negotiateProtocolVersionWithClientMinimumVersion:RNRProtocolVersionMinimumCompatible
        clientMaximumVersion:RNRProtocolVersionCurrent
        completion:^(RNRProtocolVersion negotiatedVersion, NSError *error) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) {
                return;
            }
            if (self.isInvalidated) {
                completion(nil, [self errorWithCode:RNRProtocolErrorHostUnavailable]);
                return;
            }
            if (error) {
                completion(nil, error);
                return;
            }
            if (negotiatedVersion < RNRProtocolVersionMinimumCompatible ||
                negotiatedVersion > RNRProtocolVersionCurrent) {
                completion(nil, [self errorWithCode:RNRProtocolErrorIncompatibleVersion]);
                return;
            }

            self.ready = YES;
            [self forwardOpenRequest:request completion:completion];
        }];
}

- (void)closeSessionWithIdentifier:(RNRSessionIdentifier *)sessionIdentifier
                        completion:(RNRSessionCoordinatorCloseCompletion)completion {
    if (self.isInvalidated) {
        completion([self errorWithCode:RNRProtocolErrorHostUnavailable]);
        return;
    }
    if (![self.mutableSessionIdentifiers containsObject:sessionIdentifier]) {
        completion([self errorWithCode:RNRProtocolErrorMissingSession]);
        return;
    }

    __weak typeof(self) weakSelf = self;
    [self.hostConnection closeSessionWithIdentifier:sessionIdentifier completion:^(NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }
        if (!error) {
            [self.mutableSessionIdentifiers removeObject:sessionIdentifier];
        }
        completion(error);
    }];
}

- (void)invalidate {
    if (self.isInvalidated) {
        return;
    }

    self.invalidated = YES;
    self.ready = NO;
    [self.mutableSessionIdentifiers removeAllObjects];
    self.hostConnection.delegate = nil;
    [self.hostConnection invalidate];
}

- (void)hostServiceDidCloseSessionWithIdentifier:(RNRSessionIdentifier *)sessionIdentifier
                                           error:(NSError *)error {
    [self.mutableSessionIdentifiers removeObject:sessionIdentifier];
}

- (void)hostConnection:(id<RNRHostConnection>)connection
    didInvalidateWithError:(NSError *)error {
    self.invalidated = YES;
    self.ready = NO;
    [self.mutableSessionIdentifiers removeAllObjects];
    connection.delegate = nil;
}

- (void)forwardOpenRequest:(RNROpenSessionRequest *)request
                completion:(RNRSessionCoordinatorOpenCompletion)completion {
    __weak typeof(self) weakSelf = self;
    [self.hostConnection openSessionWithRequest:request
                                     completion:^(RNRSessionIdentifier *sessionIdentifier, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }
        if (self.isInvalidated) {
            completion(nil, [self errorWithCode:RNRProtocolErrorHostUnavailable]);
            return;
        }
        if (error) {
            completion(nil, error);
            return;
        }
        if (!sessionIdentifier) {
            completion(nil, [self errorWithCode:RNRProtocolErrorInvalidRequest]);
            return;
        }

        [self.mutableSessionIdentifiers addObject:sessionIdentifier];
        completion(sessionIdentifier, nil);
    }];
}

- (NSError *)errorWithCode:(RNRProtocolErrorCode)code {
    return [NSError errorWithDomain:RNRProtocolErrorDomain code:code userInfo:nil];
}

@end
