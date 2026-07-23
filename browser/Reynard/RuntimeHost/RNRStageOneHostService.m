#import "RNRStageOneHostService.h"

#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <mach/kern_return.h>
#import <ReynardProtocol/ReynardProtocol.h>
#import <TargetConditionals.h>

typedef kern_return_t (*RNRExposeLocalMessagePortFunction)(CFMessagePortRef);

#if !TARGET_OS_SIMULATOR
static RNRExposeLocalMessagePortFunction RNRRocketBootstrapExposeFunction(void)
{
    static RNRExposeLocalMessagePortFunction function;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        function = (RNRExposeLocalMessagePortFunction)dlsym(
            RTLD_DEFAULT,
            "rocketbootstrap_cfmessageportexposelocal"
        );
        if (function) {
            return;
        }

        void *handle = dlopen("librocketbootstrap.dylib", RTLD_LAZY | RTLD_LOCAL);
        if (!handle) {
            handle = dlopen("/usr/lib/librocketbootstrap.dylib", RTLD_LAZY | RTLD_LOCAL);
        }
        if (handle) {
            function = (RNRExposeLocalMessagePortFunction)dlsym(
                handle,
                "rocketbootstrap_cfmessageportexposelocal"
            );
        }
    });
    return function;
}
#endif

static NSError *RNRHostError(RNRProtocolErrorCode code)
{
    return [NSError errorWithDomain:RNRProtocolErrorDomain code:code userInfo:nil];
}

@interface RNRStageOneHostService : NSObject

@property (class, nonatomic, readonly) RNRStageOneHostService *sharedService;

- (BOOL)startWithError:(NSError * _Nullable * _Nullable)error;

@end

@interface RNRStageOneHostService (MessagePortCallback)

- (NSData *)responseDataForMessageIdentifier:(SInt32)messageIdentifier
                                  requestData:(NSData *)requestData;

@end

static CFDataRef RNRHostMessagePortCallback(CFMessagePortRef local,
                                            SInt32 messageIdentifier,
                                            CFDataRef data,
                                            void *info)
{
    (void)local;
    RNRStageOneHostService *service = (__bridge RNRStageOneHostService *)info;
    NSData *requestData = (__bridge NSData *)data;
    NSData *responseData = [service responseDataForMessageIdentifier:messageIdentifier
                                                         requestData:requestData];
    return CFBridgingRetain(responseData);
}

@interface RNRStageOneHostService ()

@property (nonatomic) CFMessagePortRef messagePort;
@property (nonatomic) CFRunLoopSourceRef runLoopSource;
@property (nonatomic, strong) NSMutableSet<RNRSessionIdentifier *> *sessionIdentifiers;

@end


@implementation RNRStageOneHostService

void RNRStartStageOneHostService(void)
{
    NSError *error = nil;
    if (![RNRStageOneHostService.sharedService startWithError:&error]) {
        NSLog(@"Reynard Stage 1 runtime host did not start: %@", error);
    }
}

+ (RNRStageOneHostService *)sharedService
{
    static RNRStageOneHostService *service;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        service = [[self alloc] init];
    });
    return service;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _sessionIdentifiers = [NSMutableSet set];
    }
    return self;
}

- (void)dealloc
{
    if (_runLoopSource) {
        CFRunLoopSourceInvalidate(_runLoopSource);
        CFRelease(_runLoopSource);
    }
    if (_messagePort) {
        CFMessagePortInvalidate(_messagePort);
        CFRelease(_messagePort);
    }
}

- (BOOL)startWithError:(NSError **)error
{
    if (self.messagePort) {
        return YES;
    }

    CFMessagePortContext context = {0, (__bridge void *)self, NULL, NULL, NULL};
    Boolean shouldFreeInfo = false;
    CFMessagePortRef messagePort = CFMessagePortCreateLocal(
        kCFAllocatorDefault,
        (__bridge CFStringRef)RNRRuntimeServiceName,
        RNRHostMessagePortCallback,
        &context,
        &shouldFreeInfo
    );
    if (!messagePort) {
        if (error) {
            *error = RNRHostError(RNRProtocolErrorHostUnavailable);
        }
        return NO;
    }

#if !TARGET_OS_SIMULATOR
    RNRExposeLocalMessagePortFunction expose = RNRRocketBootstrapExposeFunction();
    if (!expose || expose(messagePort) != KERN_SUCCESS) {
        CFMessagePortInvalidate(messagePort);
        CFRelease(messagePort);
        if (error) {
            *error = RNRHostError(RNRProtocolErrorHostUnavailable);
        }
        return NO;
    }
#endif

    CFRunLoopSourceRef source = CFMessagePortCreateRunLoopSource(
        kCFAllocatorDefault,
        messagePort,
        0
    );
    if (!source) {
        CFMessagePortInvalidate(messagePort);
        CFRelease(messagePort);
        if (error) {
            *error = RNRHostError(RNRProtocolErrorUnknown);
        }
        return NO;
    }

    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
    self.messagePort = messagePort;
    self.runLoopSource = source;
    return YES;
}

- (NSData *)responseDataForMessageIdentifier:(SInt32)messageIdentifier
                                  requestData:(NSData *)requestData
{
    id propertyList = [NSPropertyListSerialization propertyListWithData:requestData
                                                                options:NSPropertyListImmutable
                                                                 format:NULL
                                                                  error:nil];
    NSDictionary<NSString *, id> *request = [propertyList isKindOfClass:NSDictionary.class]
        ? propertyList
        : nil;

    NSDictionary<NSString *, id> *response;
    if (!request) {
        response = [self errorResponse:RNRProtocolErrorInvalidRequest];
    } else {
        switch (messageIdentifier) {
            case RNRRuntimeMessageNegotiateProtocol:
                response = [self negotiateProtocolWithRequest:request];
                break;
            case RNRRuntimeMessageOpenSession:
                response = [self openSessionWithRequest:request];
                break;
            case RNRRuntimeMessageCloseSession:
                response = [self closeSessionWithRequest:request];
                break;
            default:
                response = [self errorResponse:RNRProtocolErrorInvalidRequest];
                break;
        }
    }

    NSError *serializationError = nil;
    NSData *responseData = [NSPropertyListSerialization dataWithPropertyList:response
                                                                      format:NSPropertyListBinaryFormat_v1_0
                                                                     options:0
                                                                       error:&serializationError];
    NSAssert(responseData != nil, @"Runtime response serialization failed: %@", serializationError);
    return responseData;
}

- (NSDictionary<NSString *, id> *)negotiateProtocolWithRequest:(NSDictionary<NSString *, id> *)request
{
    NSNumber *minimum = request[RNRRuntimeWireClientMinimumVersionKey];
    NSNumber *maximum = request[RNRRuntimeWireClientMaximumVersionKey];
    if (![minimum isKindOfClass:NSNumber.class] ||
        ![maximum isKindOfClass:NSNumber.class] ||
        minimum.longLongValue <= RNRProtocolVersionInvalid ||
        maximum.longLongValue < minimum.longLongValue) {
        return [self errorResponse:RNRProtocolErrorInvalidRequest];
    }

    RNRProtocolVersion negotiated = MIN(maximum.longLongValue, RNRProtocolVersionCurrent);
    if (negotiated < MAX(minimum.longLongValue, RNRProtocolVersionMinimumCompatible)) {
        return @{
            RNRRuntimeWireNegotiatedVersionKey: @(RNRProtocolVersionInvalid),
            RNRRuntimeWireErrorCodeKey: @(RNRProtocolErrorIncompatibleVersion),
        };
    }
    return @{RNRRuntimeWireNegotiatedVersionKey: @(negotiated)};
}

- (NSDictionary<NSString *, id> *)openSessionWithRequest:(NSDictionary<NSString *, id> *)request
{
    NSData *archive = request[RNRRuntimeWireArchivedObjectKey];
    if (![archive isKindOfClass:NSData.class]) {
        return [self errorResponse:RNRProtocolErrorInvalidRequest];
    }

    RNROpenSessionRequest *openRequest = [NSKeyedUnarchiver
        unarchivedObjectOfClass:RNROpenSessionRequest.class
        fromData:archive
        error:nil];
    NSString *scheme = openRequest.initialURL.scheme.lowercaseString;
    if (!openRequest || !([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) {
        return [self errorResponse:RNRProtocolErrorInvalidRequest];
    }

    RNRSessionIdentifier *identifier = [[RNRSessionIdentifier alloc] init];
    NSData *identifierArchive = [NSKeyedArchiver archivedDataWithRootObject:identifier
                                                      requiringSecureCoding:YES
                                                                      error:nil];
    if (!identifierArchive) {
        return [self errorResponse:RNRProtocolErrorUnknown];
    }
    [self.sessionIdentifiers addObject:identifier];
    return @{RNRRuntimeWireArchivedObjectKey: identifierArchive};
}

- (NSDictionary<NSString *, id> *)closeSessionWithRequest:(NSDictionary<NSString *, id> *)request
{
    NSData *archive = request[RNRRuntimeWireArchivedObjectKey];
    if (![archive isKindOfClass:NSData.class]) {
        return [self errorResponse:RNRProtocolErrorInvalidRequest];
    }

    RNRSessionIdentifier *identifier = [NSKeyedUnarchiver
        unarchivedObjectOfClass:RNRSessionIdentifier.class
        fromData:archive
        error:nil];
    if (!identifier) {
        return [self errorResponse:RNRProtocolErrorInvalidRequest];
    }
    if (![self.sessionIdentifiers containsObject:identifier]) {
        return [self errorResponse:RNRProtocolErrorMissingSession];
    }

    [self.sessionIdentifiers removeObject:identifier];
    return @{};
}

- (NSDictionary<NSString *, id> *)errorResponse:(RNRProtocolErrorCode)code
{
    return @{RNRRuntimeWireErrorCodeKey: @(code)};
}

@end
