#import "RNRCFMessagePortTransport.h"

#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <os/log.h>
#import <TargetConditionals.h>
#import <unistd.h>

static const NSUInteger RNRHostLookupAttemptCount = 12;
static const NSTimeInterval RNRHostLookupRetryDelay = 0.25;
static const CFTimeInterval RNRMessageSendTimeout = 3.0;
static const CFTimeInterval RNRMessageReceiveTimeout = 3.0;

static os_log_t RNRClientTransportLog(void)
{
    static os_log_t log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        log = os_log_create("in.benyell.reynard.runtime", "client-transport");
    });
    return log;
}

typedef CFMessagePortRef (*RNRCFMessagePortCreateRemoteFunction)(CFAllocatorRef, CFStringRef);

static RNRCFMessagePortCreateRemoteFunction RNRRocketBootstrapCreateRemoteFunction(void)
{
    static RNRCFMessagePortCreateRemoteFunction function;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        function = (RNRCFMessagePortCreateRemoteFunction)dlsym(
            RTLD_DEFAULT,
            "rocketbootstrap_cfmessageportcreateremote"
        );
        if (function) {
            return;
        }

        void *handle = dlopen("librocketbootstrap.dylib", RTLD_LAZY | RTLD_LOCAL);
        if (!handle) {
            handle = dlopen("/usr/lib/librocketbootstrap.dylib", RTLD_LAZY | RTLD_LOCAL);
        }
        if (handle) {
            function = (RNRCFMessagePortCreateRemoteFunction)dlsym(
                handle,
                "rocketbootstrap_cfmessageportcreateremote"
            );
        }
    });
    return function;
}

static CFMessagePortRef RNRCreateRemoteMessagePort(NSString *serviceName,
                                                    BOOL *usedRocketBootstrap)
{
    RNRCFMessagePortCreateRemoteFunction function = RNRRocketBootstrapCreateRemoteFunction();
    if (function) {
        if (usedRocketBootstrap) {
            *usedRocketBootstrap = YES;
        }
        return function(kCFAllocatorDefault, (__bridge CFStringRef)serviceName);
    }
    if (usedRocketBootstrap) {
        *usedRocketBootstrap = NO;
    }
    return CFMessagePortCreateRemote(kCFAllocatorDefault, (__bridge CFStringRef)serviceName);
}

static NSError *RNRTransportError(RNRProtocolErrorCode code)
{
    return [NSError errorWithDomain:RNRProtocolErrorDomain code:code userInfo:nil];
}

static NSTimeInterval RNRTransportMonotonicTime(void)
{
    return NSProcessInfo.processInfo.systemUptime;
}

void RNRActivateStageOneHost(void)
{
    os_log_info(RNRClientTransportLog(),
                "activation dispatch pid=%{public}d route=runtime-host",
                getpid());
    dispatch_async(dispatch_get_main_queue(), ^{
        Class applicationClass = NSClassFromString(@"UIApplication");
        SEL sharedApplicationSelector = NSSelectorFromString(@"sharedApplication");
        if (!applicationClass || ![applicationClass respondsToSelector:sharedApplicationSelector]) {
            return;
        }

        id application = ((id (*)(id, SEL))objc_msgSend)(applicationClass, sharedApplicationSelector);
        SEL openURLSelector = NSSelectorFromString(@"openURL:options:completionHandler:");
        if (![application respondsToSelector:openURLSelector]) {
            return;
        }

        NSURL *URL = [NSURL URLWithString:@"reynard://runtime-host"];
        void (^completion)(BOOL) = ^(BOOL success) {
            os_log_info(RNRClientTransportLog(),
                        "activation completion pid=%{public}d success=%{public}d",
                        getpid(),
                        success);
        };
        ((void (*)(id, SEL, NSURL *, NSDictionary *, id))objc_msgSend)(
            application,
            openURLSelector,
            URL,
            @{},
            completion
        );
    });
}

@interface RNRCFMessagePortTransport ()

@property (nonatomic, copy) NSString *serviceName;
@property (nonatomic, copy) RNRHostActivationHandler activationHandler;
@property (nonatomic, copy, nullable) RNRMessageTransportDiagnosticHandler diagnosticHandler;
@property (nonatomic) dispatch_queue_t queue;
@property (nonatomic, getter=isInvalidated) BOOL invalidated;

@end

@implementation RNRCFMessagePortTransport

- (instancetype)initWithServiceName:(NSString *)serviceName
                   activationHandler:(RNRHostActivationHandler)activationHandler
{
    return [self initWithServiceName:serviceName
                    activationHandler:activationHandler
                    diagnosticHandler:nil];
}

- (instancetype)initWithServiceName:(NSString *)serviceName
                   activationHandler:(RNRHostActivationHandler)activationHandler
                   diagnosticHandler:(RNRMessageTransportDiagnosticHandler)diagnosticHandler
{
    self = [super init];
    if (self) {
        _serviceName = [serviceName copy];
        _activationHandler = [activationHandler copy];
        _diagnosticHandler = [diagnosticHandler copy];
        _queue = dispatch_queue_create("in.benyell.ReynardServices.message-port", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)sendMessageIdentifier:(RNRRuntimeMessageIdentifier)messageIdentifier
                      payload:(NSDictionary<NSString *, id> *)payload
                   completion:(RNRMessageTransportCompletion)completion
{
    dispatch_async(self.queue, ^{
        [self sendMessageIdentifier:messageIdentifier
                            payload:payload
                            attempt:0
                          startedAt:RNRTransportMonotonicTime()
                         completion:completion];
    });
}

- (void)invalidate
{
    dispatch_async(self.queue, ^{
        self.invalidated = YES;
        [self emitDiagnosticEvent:RNRMessageTransportDiagnosticEventInvalidated
                messageIdentifier:0
                    attemptNumber:0
                          duration:0
                             error:nil];
    });
}

- (void)sendMessageIdentifier:(RNRRuntimeMessageIdentifier)messageIdentifier
                      payload:(NSDictionary<NSString *, id> *)payload
                      attempt:(NSUInteger)attempt
                    startedAt:(NSTimeInterval)startedAt
                   completion:(RNRMessageTransportCompletion)completion
{
    if (self.isInvalidated) {
        NSError *error = RNRTransportError(RNRProtocolErrorConnectionInterrupted);
        [self emitDiagnosticEvent:RNRMessageTransportDiagnosticEventRequestCompleted
                messageIdentifier:messageIdentifier
                    attemptNumber:attempt + 1
                          duration:RNRTransportMonotonicTime() - startedAt
                             error:error];
        [self finishWithResponse:nil
                          error:error
                     completion:completion];
        return;
    }

    NSUInteger attemptNumber = attempt + 1;
    [self emitDiagnosticEvent:RNRMessageTransportDiagnosticEventDiscoveryAttempt
            messageIdentifier:messageIdentifier
                attemptNumber:attemptNumber
                      duration:RNRTransportMonotonicTime() - startedAt
                         error:nil];

    BOOL usedRocketBootstrap = NO;
    CFMessagePortRef remotePort = RNRCreateRemoteMessagePort(self.serviceName,
                                                             &usedRocketBootstrap);
    if (!remotePort) {
        if (attempt == 0) {
            [self emitDiagnosticEvent:RNRMessageTransportDiagnosticEventActivationRequested
                    messageIdentifier:messageIdentifier
                        attemptNumber:attemptNumber
                              duration:RNRTransportMonotonicTime() - startedAt
                                 error:nil];
            self.activationHandler();
        }
        if (attempt + 1 < RNRHostLookupAttemptCount) {
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW, (int64_t)(RNRHostLookupRetryDelay * NSEC_PER_SEC)),
                self.queue,
                ^{
                    [self sendMessageIdentifier:messageIdentifier
                                        payload:payload
                                        attempt:attempt + 1
                                      startedAt:startedAt
                                     completion:completion];
                }
            );
            return;
        }

        NSError *error = RNRTransportError(RNRProtocolErrorHostUnavailable);
        [self emitDiagnosticEvent:RNRMessageTransportDiagnosticEventRequestCompleted
                messageIdentifier:messageIdentifier
                    attemptNumber:attemptNumber
                          duration:RNRTransportMonotonicTime() - startedAt
                             error:error];
        [self finishWithResponse:nil error:error completion:completion];
        return;
    }

    os_log_info(RNRClientTransportLog(),
                "port discovered pid=%{public}d message=%{public}d attempt=%{public}lu/%{public}lu bridge=%{public}s",
                getpid(),
                messageIdentifier,
                (unsigned long)attemptNumber,
                (unsigned long)RNRHostLookupAttemptCount,
                usedRocketBootstrap ? "rocketbootstrap" : "local");
    [self emitDiagnosticEvent:RNRMessageTransportDiagnosticEventPortDiscovered
            messageIdentifier:messageIdentifier
                attemptNumber:attemptNumber
                      duration:RNRTransportMonotonicTime() - startedAt
                         error:nil];

    NSError *serializationError = nil;
    NSData *requestData = [NSPropertyListSerialization dataWithPropertyList:payload
                                                                     format:NSPropertyListBinaryFormat_v1_0
                                                                    options:0
                                                                      error:&serializationError];
    if (!requestData) {
        CFRelease(remotePort);
        [self emitDiagnosticEvent:RNRMessageTransportDiagnosticEventRequestCompleted
                messageIdentifier:messageIdentifier
                    attemptNumber:attemptNumber
                          duration:RNRTransportMonotonicTime() - startedAt
                             error:serializationError];
        [self finishWithResponse:nil error:serializationError completion:completion];
        return;
    }

    CFDataRef replyData = NULL;
    [self emitDiagnosticEvent:RNRMessageTransportDiagnosticEventRequestStarted
            messageIdentifier:messageIdentifier
                attemptNumber:attemptNumber
                      duration:RNRTransportMonotonicTime() - startedAt
                         error:nil];
    SInt32 result = CFMessagePortSendRequest(
        remotePort,
        messageIdentifier,
        (__bridge CFDataRef)requestData,
        RNRMessageSendTimeout,
        RNRMessageReceiveTimeout,
        kCFRunLoopDefaultMode,
        &replyData
    );
    CFRelease(remotePort);

    if (result != kCFMessagePortSuccess || !replyData) {
        if (replyData) {
            CFRelease(replyData);
        }
        BOOL timedOut = result == kCFMessagePortSendTimeout ||
            result == kCFMessagePortReceiveTimeout;
        RNRProtocolErrorCode code = result == kCFMessagePortIsInvalid ||
            result == kCFMessagePortBecameInvalidError
            ? RNRProtocolErrorConnectionInterrupted
            : RNRProtocolErrorHostUnavailable;
        NSError *error = RNRTransportError(code);
        os_log_error(RNRClientTransportLog(),
                     "request failure pid=%{public}d message=%{public}d transport_result=%{public}d timeout=%{public}d",
                     getpid(),
                     messageIdentifier,
                     result,
                     timedOut);
        if (timedOut) {
            [self emitDiagnosticEvent:RNRMessageTransportDiagnosticEventTimeout
                    messageIdentifier:messageIdentifier
                        attemptNumber:attemptNumber
                              duration:RNRTransportMonotonicTime() - startedAt
                                 error:error];
        }
        [self emitDiagnosticEvent:RNRMessageTransportDiagnosticEventRequestCompleted
                messageIdentifier:messageIdentifier
                    attemptNumber:attemptNumber
                          duration:RNRTransportMonotonicTime() - startedAt
                             error:error];
        [self finishWithResponse:nil error:error completion:completion];
        return;
    }

    NSData *data = CFBridgingRelease(replyData);
    NSError *replyError = nil;
    id propertyList = [NSPropertyListSerialization propertyListWithData:data
                                                                options:NSPropertyListImmutable
                                                                 format:NULL
                                                                  error:&replyError];
    if (![propertyList isKindOfClass:[NSDictionary class]]) {
        NSError *error = replyError ?: RNRTransportError(RNRProtocolErrorInvalidRequest);
        [self emitDiagnosticEvent:RNRMessageTransportDiagnosticEventRequestCompleted
                messageIdentifier:messageIdentifier
                    attemptNumber:attemptNumber
                          duration:RNRTransportMonotonicTime() - startedAt
                             error:error];
        [self finishWithResponse:nil
                          error:error
                     completion:completion];
        return;
    }

    [self emitDiagnosticEvent:RNRMessageTransportDiagnosticEventRequestCompleted
            messageIdentifier:messageIdentifier
                attemptNumber:attemptNumber
                      duration:RNRTransportMonotonicTime() - startedAt
                         error:nil];
    [self finishWithResponse:propertyList error:nil completion:completion];
}

- (void)emitDiagnosticEvent:(RNRMessageTransportDiagnosticEvent)event
          messageIdentifier:(RNRRuntimeMessageIdentifier)messageIdentifier
              attemptNumber:(NSUInteger)attemptNumber
                    duration:(NSTimeInterval)duration
                       error:(NSError *)error
{
    NSString *domain = error.domain ?: @"none";
    os_log_info(RNRClientTransportLog(),
                "transport event pid=%{public}d event=%{public}lu message=%{public}d attempt=%{public}lu/%{public}lu duration_ms=%{public}.1f error_domain=%{public}@ error_code=%{public}ld",
                getpid(),
                (unsigned long)event,
                messageIdentifier,
                (unsigned long)attemptNumber,
                (unsigned long)RNRHostLookupAttemptCount,
                duration * 1000.0,
                domain,
                (long)error.code);
    if (self.diagnosticHandler) {
        self.diagnosticHandler(event,
                               messageIdentifier,
                               attemptNumber,
                               RNRHostLookupAttemptCount,
                               duration,
                               error);
    }
}

- (void)finishWithResponse:(NSDictionary<NSString *, id> *)response
                      error:(NSError *)error
                 completion:(RNRMessageTransportCompletion)completion
{
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(response, error);
    });
}

@end
