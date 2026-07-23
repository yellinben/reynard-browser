#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const RNRProtocolErrorDomain;

typedef NS_ERROR_ENUM(RNRProtocolErrorDomain, RNRProtocolErrorCode) {
    RNRProtocolErrorUnknown = 1,
    RNRProtocolErrorIncompatibleVersion = 2,
    RNRProtocolErrorInvalidRequest = 3,
    RNRProtocolErrorHostUnavailable = 4,
    RNRProtocolErrorMissingSession = 5,
    RNRProtocolErrorConnectionInterrupted = 6,
    RNRProtocolErrorSessionTerminated = 7,
};

NS_ASSUME_NONNULL_END
