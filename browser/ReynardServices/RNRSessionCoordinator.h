#import <Foundation/Foundation.h>
#import <ReynardProtocol/ReynardProtocol.h>

#import "RNRHostConnection.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^RNRSessionCoordinatorOpenCompletion)(
    RNRSessionIdentifier * _Nullable sessionIdentifier,
    NSError * _Nullable error);
typedef void (^RNRSessionCoordinatorCloseCompletion)(NSError * _Nullable error);

@interface RNRSessionCoordinator : NSObject <RNRHostConnectionDelegate>

@property (nonatomic, copy, readonly) NSSet<RNRSessionIdentifier *> *activeSessionIdentifiers;
@property (nonatomic, readonly, getter=isReady) BOOL ready;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)initWithHostConnection:(id<RNRHostConnection>)hostConnection NS_DESIGNATED_INITIALIZER;

- (void)openSessionWithRequest:(RNROpenSessionRequest *)request
                    completion:(RNRSessionCoordinatorOpenCompletion)completion;
- (void)closeSessionWithIdentifier:(RNRSessionIdentifier *)sessionIdentifier
                        completion:(RNRSessionCoordinatorCloseCompletion)completion;
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
