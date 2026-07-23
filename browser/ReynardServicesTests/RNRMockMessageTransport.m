#import "RNRMockMessageTransport.h"

@implementation RNRMockMessageTransport

- (instancetype)init
{
    self = [super init];
    if (self) {
        _response = @{};
    }
    return self;
}

- (void)sendMessageIdentifier:(RNRRuntimeMessageIdentifier)messageIdentifier
                      payload:(NSDictionary<NSString *,id> *)payload
                   completion:(RNRMessageTransportCompletion)completion
{
    self.receivedMessageIdentifier = messageIdentifier;
    self.receivedPayload = payload;
    completion(self.response, self.error);
}

- (void)invalidate
{
    self.invalidated = YES;
}

@end
