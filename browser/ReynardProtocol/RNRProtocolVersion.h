#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef int64_t RNRProtocolVersion;

/// Sentinel used when no compatible protocol version was negotiated.
FOUNDATION_EXPORT const RNRProtocolVersion RNRProtocolVersionInvalid;
/// Oldest protocol version this build can understand.
FOUNDATION_EXPORT const RNRProtocolVersion RNRProtocolVersionMinimumCompatible;
/// Newest protocol version this build can understand.
FOUNDATION_EXPORT const RNRProtocolVersion RNRProtocolVersionCurrent;

NS_ASSUME_NONNULL_END
