#import "RNRIPCSmokeState.h"

NSString *RNRIPCSmokeSessionStateName(RNRIPCSmokeSessionState state)
{
    switch (state) {
        case RNRIPCSmokeSessionStateActive:
            return @"active-opaque";
        case RNRIPCSmokeSessionStateIndeterminate:
            return @"indeterminate";
        case RNRIPCSmokeSessionStateNone:
            return @"none";
    }
    return @"unknown";
}

@interface RNRIPCSmokeState ()

@property (nonatomic, readwrite, getter=isBusy) BOOL busy;
@property (nonatomic, readwrite) RNRProtocolVersion negotiatedVersion;
@property (nonatomic, readwrite) RNRIPCSmokeSessionState sessionState;
@property (nonatomic, copy, readwrite, nullable) NSUUID *operationIdentifier;
@property (nonatomic, copy, readwrite, nullable) NSString *operationName;
@property (nonatomic, copy, readwrite) NSString *resultSummary;

@end

@implementation RNRIPCSmokeState

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self reset];
    }
    return self;
}

- (BOOL)beginOperationNamed:(NSString *)operationName
{
    NSParameterAssert(operationName.length > 0);
    if (self.isBusy) {
        return NO;
    }

    self.busy = YES;
    self.operationIdentifier = [NSUUID UUID];
    self.operationName = [operationName copy];
    return YES;
}

- (void)finishOperationWithDuration:(NSTimeInterval)duration
                   negotiatedVersion:(RNRProtocolVersion)negotiatedVersion
                        sessionState:(RNRIPCSmokeSessionState)sessionState
                               error:(NSError *)error
{
    NSAssert(self.isBusy, @"A smoke operation must begin before it finishes.");
    NSString *errorDomain = error.domain ?: @"none";
    NSInteger errorCode = error ? error.code : 0;
    NSString *identifier = self.operationIdentifier.UUIDString ?: @"none";
    NSString *operation = self.operationName ?: @"unknown";

    self.negotiatedVersion = negotiatedVersion;
    self.sessionState = sessionState;
    self.resultSummary = [NSString stringWithFormat:
        @"operation=%@\n"
         "operation_id=%@\n"
         "duration_ms=%.1f\n"
         "negotiated_version=%lld\n"
         "error_domain=%@\n"
         "error_code=%ld\n"
         "session_state=%@",
        operation,
        identifier,
        duration * 1000.0,
        negotiatedVersion,
        errorDomain,
        (long)errorCode,
        RNRIPCSmokeSessionStateName(sessionState)];
    self.busy = NO;
}

- (void)reset
{
    self.busy = NO;
    self.negotiatedVersion = RNRProtocolVersionInvalid;
    self.sessionState = RNRIPCSmokeSessionStateNone;
    self.operationIdentifier = nil;
    self.operationName = nil;
    self.resultSummary = @"operation=none\n"
                         "duration_ms=0.0\n"
                         "negotiated_version=0\n"
                         "error_domain=none\n"
                         "error_code=0\n"
                         "session_state=none";
}

@end
