#import <Foundation/Foundation.h>
#import <ReynardProtocol/ReynardProtocol.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^RNRMessageTransportCompletion)(NSDictionary<NSString *, id> * _Nullable response,
                                               NSError * _Nullable error);

typedef NS_ENUM(NSUInteger, RNRMessageTransportDiagnosticEvent) {
    RNRMessageTransportDiagnosticEventDiscoveryAttempt = 1,
    RNRMessageTransportDiagnosticEventActivationRequested = 2,
    RNRMessageTransportDiagnosticEventPortDiscovered = 3,
    RNRMessageTransportDiagnosticEventRequestStarted = 4,
    RNRMessageTransportDiagnosticEventRequestCompleted = 5,
    RNRMessageTransportDiagnosticEventInvalidated = 6,
    RNRMessageTransportDiagnosticEventTimeout = 7,
};

/// Development diagnostics never include a request payload, URL, or session identifier.
typedef void (^RNRMessageTransportDiagnosticHandler)(
    RNRMessageTransportDiagnosticEvent event,
    RNRRuntimeMessageIdentifier messageIdentifier,
    NSUInteger attemptNumber,
    NSUInteger maximumAttemptCount,
    NSTimeInterval duration,
    NSError * _Nullable error);

@protocol RNRMessageTransport <NSObject>

- (void)sendMessageIdentifier:(RNRRuntimeMessageIdentifier)messageIdentifier
                      payload:(NSDictionary<NSString *, id> *)payload
                   completion:(RNRMessageTransportCompletion)completion;

- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
