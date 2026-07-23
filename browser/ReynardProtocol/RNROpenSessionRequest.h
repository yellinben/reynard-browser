#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RNROpenSessionRequest : NSObject <NSCopying, NSSecureCoding>

@property (nonatomic, readonly, copy) NSURL *initialURL;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
/// Creates the smallest version-one session request. URL policy is validated by the host.
- (instancetype)initWithInitialURL:(NSURL *)initialURL NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
