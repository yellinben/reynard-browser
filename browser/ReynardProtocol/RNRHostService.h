#import <Foundation/Foundation.h>

#import "RNRProtocolVersion.h"

@class RNROpenSessionRequest;
@class RNRSessionIdentifier;

NS_ASSUME_NONNULL_BEGIN

@protocol RNRHostService <NSObject>

/// Selects the highest version supported by both peers. Incompatibility returns version zero and an error.
- (void)negotiateProtocolVersionWithClientMinimumVersion:(RNRProtocolVersion)clientMinimumVersion
                                     clientMaximumVersion:(RNRProtocolVersion)clientMaximumVersion
                                               completion:(void (^)(RNRProtocolVersion negotiatedVersion,
                                                                    NSError * _Nullable error))completion;

- (void)openSessionWithRequest:(RNROpenSessionRequest *)request
                    completion:(void (^)(RNRSessionIdentifier * _Nullable sessionIdentifier,
                                         NSError * _Nullable error))completion;

/// Acknowledges client-requested closure. Host-requested closure uses RNRClientLifecycle.
- (void)closeSessionWithIdentifier:(RNRSessionIdentifier *)sessionIdentifier
                        completion:(void (^)(NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
