#import <Foundation/Foundation.h>

#import "RNRMessageTransport.h"

NS_ASSUME_NONNULL_BEGIN

@interface RNRMockMessageTransport : NSObject <RNRMessageTransport>

@property (nonatomic) RNRRuntimeMessageIdentifier receivedMessageIdentifier;
@property (nonatomic, copy, nullable) NSDictionary<NSString *, id> *receivedPayload;
@property (nonatomic, copy) NSDictionary<NSString *, id> *response;
@property (nonatomic, strong, nullable) NSError *error;
@property (nonatomic, getter=isInvalidated) BOOL invalidated;

@end

NS_ASSUME_NONNULL_END
