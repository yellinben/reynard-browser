#import <Foundation/Foundation.h>
#import <ReynardProtocol/ReynardProtocol.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, RNRIPCSmokeSessionState) {
    RNRIPCSmokeSessionStateNone = 0,
    RNRIPCSmokeSessionStateActive = 1,
    RNRIPCSmokeSessionStateIndeterminate = 2,
};

FOUNDATION_EXPORT NSString *RNRIPCSmokeSessionStateName(RNRIPCSmokeSessionState state);

/// Single-flight state and deliberately redacted result formatting for the development harness.
@interface RNRIPCSmokeState : NSObject

@property (nonatomic, readonly, getter=isBusy) BOOL busy;
@property (nonatomic, readonly) RNRProtocolVersion negotiatedVersion;
@property (nonatomic, readonly) RNRIPCSmokeSessionState sessionState;
@property (nonatomic, copy, readonly, nullable) NSUUID *operationIdentifier;
@property (nonatomic, copy, readonly, nullable) NSString *operationName;
@property (nonatomic, copy, readonly) NSString *resultSummary;

/// Returns NO while another operation is in flight. Rejected calls must not contact the host.
- (BOOL)beginOperationNamed:(NSString *)operationName;

- (void)finishOperationWithDuration:(NSTimeInterval)duration
                   negotiatedVersion:(RNRProtocolVersion)negotiatedVersion
                        sessionState:(RNRIPCSmokeSessionState)sessionState
                               error:(nullable NSError *)error;

- (void)reset;

@end

NS_ASSUME_NONNULL_END
