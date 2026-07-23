#import <Foundation/Foundation.h>
#import <ReynardProtocol/ReynardProtocol.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^RNRMessageTransportCompletion)(NSDictionary<NSString *, id> * _Nullable response,
                                               NSError * _Nullable error);

@protocol RNRMessageTransport <NSObject>

- (void)sendMessageIdentifier:(RNRRuntimeMessageIdentifier)messageIdentifier
                      payload:(NSDictionary<NSString *, id> *)payload
                   completion:(RNRMessageTransportCompletion)completion;

- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
