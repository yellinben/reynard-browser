#import <Foundation/Foundation.h>
#import <ReynardProtocol/ReynardProtocol.h>

NS_ASSUME_NONNULL_BEGIN

@protocol RNRHostConnection;

@protocol RNRHostConnectionDelegate <RNRClientLifecycle>

- (void)hostConnection:(id<RNRHostConnection>)connection
    didInvalidateWithError:(nullable NSError *)error;

@end

@protocol RNRHostConnection <RNRHostService>

@property (nonatomic, weak, nullable) id<RNRHostConnectionDelegate> delegate;

- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
