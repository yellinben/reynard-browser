#import "RNRCFMessagePortHostConnection.h"

#import "RNRCFMessagePortTransport.h"

#import <os/log.h>
#import <unistd.h>

static os_log_t RNRClientConnectionLog(void)
{
    static os_log_t log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        log = os_log_create("in.benyell.reynard.runtime", "client-connection");
    });
    return log;
}

static NSTimeInterval RNRClientMonotonicTime(void)
{
    return NSProcessInfo.processInfo.systemUptime;
}

static void RNRLogClientOperation(NSString *operation,
                                  NSTimeInterval startedAt,
                                  RNRProtocolVersion version,
                                  NSString *sessionState,
                                  NSError *error)
{
    os_log_info(RNRClientConnectionLog(),
                "operation completion pid=%{public}d operation=%{public}@ duration_ms=%{public}.1f negotiated_version=%{public}lld session_state=%{public}@ error_domain=%{public}@ error_code=%{public}ld",
                getpid(),
                operation,
                (RNRClientMonotonicTime() - startedAt) * 1000.0,
                version,
                sessionState,
                error.domain ?: @"none",
                (long)error.code);
}

@interface RNRCFMessagePortHostConnection ()

@property (nonatomic, strong) id<RNRMessageTransport> transport;
@property (nonatomic, getter=isInvalidated) BOOL invalidated;
@property (nonatomic) RNRProtocolVersion negotiatedVersion;

@end

@implementation RNRCFMessagePortHostConnection

@synthesize delegate = _delegate;

- (instancetype)init
{
    RNRCFMessagePortTransport *transport = [[RNRCFMessagePortTransport alloc]
        initWithServiceName:RNRRuntimeServiceName
        activationHandler:^{
            RNRActivateStageOneHost();
        }];
    return [self initWithTransport:transport];
}

- (instancetype)initWithTransport:(id<RNRMessageTransport>)transport
{
    self = [super init];
    if (self) {
        _transport = transport;
        _negotiatedVersion = RNRProtocolVersionInvalid;
    }
    return self;
}

- (void)negotiateProtocolVersionWithClientMinimumVersion:(RNRProtocolVersion)clientMinimumVersion
                                     clientMaximumVersion:(RNRProtocolVersion)clientMaximumVersion
                                               completion:(void (^)(RNRProtocolVersion, NSError *))completion
{
    NSTimeInterval startedAt = RNRClientMonotonicTime();
    os_log_info(RNRClientConnectionLog(),
                "operation start pid=%{public}d operation=negotiate minimum=%{public}lld maximum=%{public}lld",
                getpid(),
                clientMinimumVersion,
                clientMaximumVersion);
    NSDictionary *payload = @{
        RNRRuntimeWireClientMinimumVersionKey: @(clientMinimumVersion),
        RNRRuntimeWireClientMaximumVersionKey: @(clientMaximumVersion),
    };
    [self.transport sendMessageIdentifier:RNRRuntimeMessageNegotiateProtocol
                                  payload:payload
                               completion:^(NSDictionary<NSString *,id> *response, NSError *error) {
        if (error) {
            self.negotiatedVersion = RNRProtocolVersionInvalid;
            RNRLogClientOperation(@"negotiate", startedAt, RNRProtocolVersionInvalid, @"unchanged", error);
            completion(RNRProtocolVersionInvalid, error);
            return;
        }
        NSError *hostError = [self errorFromResponse:response];
        NSNumber *version = response[RNRRuntimeWireNegotiatedVersionKey];
        if (hostError || ![version isKindOfClass:NSNumber.class]) {
            NSError *resultError = hostError ?: [self protocolError:RNRProtocolErrorInvalidRequest];
            self.negotiatedVersion = RNRProtocolVersionInvalid;
            RNRLogClientOperation(@"negotiate", startedAt, RNRProtocolVersionInvalid, @"unchanged", resultError);
            completion(RNRProtocolVersionInvalid, resultError);
            return;
        }
        self.negotiatedVersion = version.longLongValue;
        RNRLogClientOperation(@"negotiate", startedAt, version.longLongValue, @"unchanged", nil);
        completion(version.longLongValue, nil);
    }];
}

- (void)openSessionWithRequest:(RNROpenSessionRequest *)request
                    completion:(void (^)(RNRSessionIdentifier *, NSError *))completion
{
    NSTimeInterval startedAt = RNRClientMonotonicTime();
    os_log_info(RNRClientConnectionLog(),
                "operation start pid=%{public}d operation=open scheme=%{public}@",
                getpid(),
                request.initialURL.scheme.lowercaseString ?: @"none");
    NSError *archiveError = nil;
    NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:request
                                            requiringSecureCoding:YES
                                                            error:&archiveError];
    if (!archive) {
        RNRLogClientOperation(@"open", startedAt, self.negotiatedVersion, @"none", archiveError);
        completion(nil, archiveError);
        return;
    }

    [self.transport sendMessageIdentifier:RNRRuntimeMessageOpenSession
                                  payload:@{RNRRuntimeWireArchivedObjectKey: archive}
                               completion:^(NSDictionary<NSString *,id> *response, NSError *error) {
        if (error) {
            RNRLogClientOperation(@"open", startedAt, self.negotiatedVersion, @"unknown", error);
            completion(nil, error);
            return;
        }
        NSError *hostError = [self errorFromResponse:response];
        NSData *identifierArchive = response[RNRRuntimeWireArchivedObjectKey];
        if (hostError || ![identifierArchive isKindOfClass:NSData.class]) {
            NSError *resultError = hostError ?: [self protocolError:RNRProtocolErrorInvalidRequest];
            RNRLogClientOperation(@"open", startedAt, self.negotiatedVersion, @"none", resultError);
            completion(nil, resultError);
            return;
        }

        NSError *decodeError = nil;
        RNRSessionIdentifier *identifier = [NSKeyedUnarchiver
            unarchivedObjectOfClass:RNRSessionIdentifier.class
            fromData:identifierArchive
            error:&decodeError];
        RNRLogClientOperation(@"open",
                              startedAt,
                              self.negotiatedVersion,
                              identifier && !decodeError ? @"active-opaque" : @"none",
                              decodeError);
        completion(identifier, decodeError);
    }];
}

- (void)closeSessionWithIdentifier:(RNRSessionIdentifier *)sessionIdentifier
                        completion:(void (^)(NSError *))completion
{
    NSTimeInterval startedAt = RNRClientMonotonicTime();
    os_log_info(RNRClientConnectionLog(),
                "operation start pid=%{public}d operation=close session_state=opaque",
                getpid());
    NSError *archiveError = nil;
    NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:sessionIdentifier
                                            requiringSecureCoding:YES
                                                            error:&archiveError];
    if (!archive) {
        RNRLogClientOperation(@"close", startedAt, self.negotiatedVersion, @"unchanged", archiveError);
        completion(archiveError);
        return;
    }

    [self.transport sendMessageIdentifier:RNRRuntimeMessageCloseSession
                                  payload:@{RNRRuntimeWireArchivedObjectKey: archive}
                               completion:^(NSDictionary<NSString *,id> *response, NSError *error) {
        NSError *resultError = error ?: [self errorFromResponse:response];
        RNRLogClientOperation(@"close",
                              startedAt,
                              self.negotiatedVersion,
                              resultError ? @"unknown" : @"none",
                              resultError);
        completion(resultError);
    }];
}

- (void)invalidate
{
    if (self.isInvalidated) {
        return;
    }
    self.invalidated = YES;
    self.negotiatedVersion = RNRProtocolVersionInvalid;
    os_log_info(RNRClientConnectionLog(),
                "connection invalidated pid=%{public}d session_state=indeterminate error_domain=%{public}@ error_code=%{public}ld",
                getpid(),
                RNRProtocolErrorDomain,
                (long)RNRProtocolErrorConnectionInterrupted);
    [self.transport invalidate];
    id<RNRHostConnectionDelegate> delegate = self.delegate;
    self.delegate = nil;
    [delegate hostConnection:self
        didInvalidateWithError:[self protocolError:RNRProtocolErrorConnectionInterrupted]];
}

- (NSError *)errorFromResponse:(NSDictionary<NSString *, id> *)response
{
    NSNumber *errorCode = response[RNRRuntimeWireErrorCodeKey];
    if (![errorCode isKindOfClass:NSNumber.class]) {
        return nil;
    }
    return [self protocolError:errorCode.integerValue];
}

- (NSError *)protocolError:(RNRProtocolErrorCode)code
{
    return [NSError errorWithDomain:RNRProtocolErrorDomain code:code userInfo:nil];
}

@end
