#import <Foundation/Foundation.h>

#import "RNRHostConnection.h"
#import "RNRMessageTransport.h"

NS_ASSUME_NONNULL_BEGIN

@interface RNRCFMessagePortHostConnection : NSObject <RNRHostConnection>

- (instancetype)initWithTransport:(id<RNRMessageTransport>)transport NS_DESIGNATED_INITIALIZER;
- (instancetype)init;

@end

NS_ASSUME_NONNULL_END
