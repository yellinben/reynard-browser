#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RNRSessionIdentifier : NSObject <NSCopying, NSSecureCoding>

/// Creates a new opaque, value-comparable session identifier.
- (instancetype)init;

@end

NS_ASSUME_NONNULL_END
