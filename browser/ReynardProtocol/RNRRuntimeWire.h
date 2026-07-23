#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const RNRRuntimeServiceName;

typedef NS_ENUM(int32_t, RNRRuntimeMessageIdentifier) {
    RNRRuntimeMessageNegotiateProtocol = 1,
    RNRRuntimeMessageOpenSession = 2,
    RNRRuntimeMessageCloseSession = 3,
};

FOUNDATION_EXPORT NSString *const RNRRuntimeWireClientMinimumVersionKey;
FOUNDATION_EXPORT NSString *const RNRRuntimeWireClientMaximumVersionKey;
FOUNDATION_EXPORT NSString *const RNRRuntimeWireNegotiatedVersionKey;
FOUNDATION_EXPORT NSString *const RNRRuntimeWireArchivedObjectKey;
FOUNDATION_EXPORT NSString *const RNRRuntimeWireErrorCodeKey;

NS_ASSUME_NONNULL_END
