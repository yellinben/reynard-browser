#import "RNRCFMessagePortTransport.h"

#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <TargetConditionals.h>

static const NSUInteger RNRHostLookupAttemptCount = 12;
static const NSTimeInterval RNRHostLookupRetryDelay = 0.25;
static const CFTimeInterval RNRMessageSendTimeout = 3.0;
static const CFTimeInterval RNRMessageReceiveTimeout = 3.0;

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

static CFMessagePortRef RNRCreateRemoteMessagePort(NSString *serviceName)
{
    RNRCFMessagePortCreateRemoteFunction function = RNRRocketBootstrapCreateRemoteFunction();
    if (function) {
        return function(kCFAllocatorDefault, (__bridge CFStringRef)serviceName);
    }
    return CFMessagePortCreateRemote(kCFAllocatorDefault, (__bridge CFStringRef)serviceName);
}

static NSError *RNRTransportError(RNRProtocolErrorCode code)
{
    return [NSError errorWithDomain:RNRProtocolErrorDomain code:code userInfo:nil];
}

void RNRActivateStageOneHost(void)
{
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
            (void)success;
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
@property (nonatomic) dispatch_queue_t queue;
@property (nonatomic, getter=isInvalidated) BOOL invalidated;

@end

@implementation RNRCFMessagePortTransport

- (instancetype)initWithServiceName:(NSString *)serviceName
                   activationHandler:(RNRHostActivationHandler)activationHandler
{
    self = [super init];
    if (self) {
        _serviceName = [serviceName copy];
        _activationHandler = [activationHandler copy];
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
                         completion:completion];
    });
}

- (void)invalidate
{
    dispatch_async(self.queue, ^{
        self.invalidated = YES;
    });
}

- (void)sendMessageIdentifier:(RNRRuntimeMessageIdentifier)messageIdentifier
                      payload:(NSDictionary<NSString *, id> *)payload
                      attempt:(NSUInteger)attempt
                   completion:(RNRMessageTransportCompletion)completion
{
    if (self.isInvalidated) {
        [self finishWithResponse:nil
                          error:RNRTransportError(RNRProtocolErrorConnectionInterrupted)
                     completion:completion];
        return;
    }

    CFMessagePortRef remotePort = RNRCreateRemoteMessagePort(self.serviceName);
    if (!remotePort) {
        if (attempt == 0) {
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
                                     completion:completion];
                }
            );
            return;
        }

        [self finishWithResponse:nil
                          error:RNRTransportError(RNRProtocolErrorHostUnavailable)
                     completion:completion];
        return;
    }

    NSError *serializationError = nil;
    NSData *requestData = [NSPropertyListSerialization dataWithPropertyList:payload
                                                                     format:NSPropertyListBinaryFormat_v1_0
                                                                    options:0
                                                                      error:&serializationError];
    if (!requestData) {
        CFRelease(remotePort);
        [self finishWithResponse:nil error:serializationError completion:completion];
        return;
    }

    CFDataRef replyData = NULL;
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
        RNRProtocolErrorCode code = result == kCFMessagePortIsInvalid
            ? RNRProtocolErrorConnectionInterrupted
            : RNRProtocolErrorHostUnavailable;
        [self finishWithResponse:nil error:RNRTransportError(code) completion:completion];
        return;
    }

    NSData *data = CFBridgingRelease(replyData);
    NSError *replyError = nil;
    id propertyList = [NSPropertyListSerialization propertyListWithData:data
                                                                options:NSPropertyListImmutable
                                                                 format:NULL
                                                                  error:&replyError];
    if (![propertyList isKindOfClass:[NSDictionary class]]) {
        [self finishWithResponse:nil
                          error:replyError ?: RNRTransportError(RNRProtocolErrorInvalidRequest)
                     completion:completion];
        return;
    }

    [self finishWithResponse:propertyList error:nil completion:completion];
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
