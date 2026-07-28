#import <Foundation/Foundation.h>

#import "RNRMessageTransport.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^RNRHostActivationHandler)(void);

@interface RNRCFMessagePortTransport : NSObject <RNRMessageTransport>

- (instancetype)initWithServiceName:(NSString *)serviceName
                   activationHandler:(RNRHostActivationHandler)activationHandler;

- (instancetype)initWithServiceName:(NSString *)serviceName
                   activationHandler:(RNRHostActivationHandler)activationHandler
                   diagnosticHandler:(nullable RNRMessageTransportDiagnosticHandler)diagnosticHandler
    NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

/// Activates the existing Reynard.app through its Stage 1 URL route without linking UIKit.
FOUNDATION_EXPORT void RNRActivateStageOneHost(void);

NS_ASSUME_NONNULL_END
