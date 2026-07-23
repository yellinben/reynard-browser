#import <Foundation/Foundation.h>

@class RNRSessionIdentifier;

NS_ASSUME_NONNULL_BEGIN

@protocol RNRClientLifecycle <NSObject>

/// Reports host-initiated session termination; a nil error means an orderly closure.
- (void)hostServiceDidCloseSessionWithIdentifier:(RNRSessionIdentifier *)sessionIdentifier
                                           error:(nullable NSError *)error;

@end

NS_ASSUME_NONNULL_END
