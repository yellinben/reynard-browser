#import "RNRCFMessagePortHostConnection.h"

#import "RNRCFMessagePortTransport.h"

@interface RNRCFMessagePortHostConnection ()

@property (nonatomic, strong) id<RNRMessageTransport> transport;
@property (nonatomic, getter=isInvalidated) BOOL invalidated;

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
    }
    return self;
}

- (void)negotiateProtocolVersionWithClientMinimumVersion:(RNRProtocolVersion)clientMinimumVersion
                                     clientMaximumVersion:(RNRProtocolVersion)clientMaximumVersion
                                               completion:(void (^)(RNRProtocolVersion, NSError *))completion
{
    NSDictionary *payload = @{
        RNRRuntimeWireClientMinimumVersionKey: @(clientMinimumVersion),
        RNRRuntimeWireClientMaximumVersionKey: @(clientMaximumVersion),
    };
    [self.transport sendMessageIdentifier:RNRRuntimeMessageNegotiateProtocol
                                  payload:payload
                               completion:^(NSDictionary<NSString *,id> *response, NSError *error) {
        if (error) {
            completion(RNRProtocolVersionInvalid, error);
            return;
        }
        NSError *hostError = [self errorFromResponse:response];
        NSNumber *version = response[RNRRuntimeWireNegotiatedVersionKey];
        if (hostError || ![version isKindOfClass:NSNumber.class]) {
            completion(RNRProtocolVersionInvalid,
                       hostError ?: [self protocolError:RNRProtocolErrorInvalidRequest]);
            return;
        }
        completion(version.longLongValue, nil);
    }];
}

- (void)openSessionWithRequest:(RNROpenSessionRequest *)request
                    completion:(void (^)(RNRSessionIdentifier *, NSError *))completion
{
    NSError *archiveError = nil;
    NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:request
                                            requiringSecureCoding:YES
                                                            error:&archiveError];
    if (!archive) {
        completion(nil, archiveError);
        return;
    }

    [self.transport sendMessageIdentifier:RNRRuntimeMessageOpenSession
                                  payload:@{RNRRuntimeWireArchivedObjectKey: archive}
                               completion:^(NSDictionary<NSString *,id> *response, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        NSError *hostError = [self errorFromResponse:response];
        NSData *identifierArchive = response[RNRRuntimeWireArchivedObjectKey];
        if (hostError || ![identifierArchive isKindOfClass:NSData.class]) {
            completion(nil, hostError ?: [self protocolError:RNRProtocolErrorInvalidRequest]);
            return;
        }

        NSError *decodeError = nil;
        RNRSessionIdentifier *identifier = [NSKeyedUnarchiver
            unarchivedObjectOfClass:RNRSessionIdentifier.class
            fromData:identifierArchive
            error:&decodeError];
        completion(identifier, decodeError);
    }];
}

- (void)closeSessionWithIdentifier:(RNRSessionIdentifier *)sessionIdentifier
                        completion:(void (^)(NSError *))completion
{
    NSError *archiveError = nil;
    NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:sessionIdentifier
                                            requiringSecureCoding:YES
                                                            error:&archiveError];
    if (!archive) {
        completion(archiveError);
        return;
    }

    [self.transport sendMessageIdentifier:RNRRuntimeMessageCloseSession
                                  payload:@{RNRRuntimeWireArchivedObjectKey: archive}
                               completion:^(NSDictionary<NSString *,id> *response, NSError *error) {
        completion(error ?: [self errorFromResponse:response]);
    }];
}

- (void)invalidate
{
    if (self.isInvalidated) {
        return;
    }
    self.invalidated = YES;
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
