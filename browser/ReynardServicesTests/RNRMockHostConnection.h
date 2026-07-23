#import <Foundation/Foundation.h>
#import <ReynardProtocol/ReynardProtocol.h>

#import "RNRHostConnection.h"

NS_ASSUME_NONNULL_BEGIN

@interface RNRMockHostConnection : NSObject <RNRHostConnection>

@property (nonatomic, weak, nullable) id<RNRHostConnectionDelegate> delegate;
@property (nonatomic) RNRProtocolVersion negotiatedVersion;
@property (nonatomic, strong, nullable) NSError *negotiationError;
@property (nonatomic, strong, nullable) RNRSessionIdentifier *openSessionIdentifier;
@property (nonatomic, strong, nullable) NSError *openError;
@property (nonatomic, strong, nullable) NSError *closeError;

@property (nonatomic, readonly) NSUInteger negotiationCount;
@property (nonatomic, readonly) NSUInteger openCount;
@property (nonatomic, readonly) NSUInteger closeCount;
@property (nonatomic, readonly) BOOL invalidateCalled;
@property (nonatomic, readonly) RNRProtocolVersion receivedMinimumVersion;
@property (nonatomic, readonly) RNRProtocolVersion receivedMaximumVersion;
@property (nonatomic, strong, readonly, nullable) RNROpenSessionRequest *receivedOpenRequest;
@property (nonatomic, strong, readonly, nullable) RNRSessionIdentifier *receivedCloseIdentifier;

- (void)simulateHostClosureForSessionIdentifier:(RNRSessionIdentifier *)sessionIdentifier
                                          error:(nullable NSError *)error;
- (void)simulateInvalidationWithError:(nullable NSError *)error;

@end

NS_ASSUME_NONNULL_END
