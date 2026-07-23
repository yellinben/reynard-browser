#import "RNROpenSessionRequest.h"

static NSString *const RNROpenSessionRequestInitialURLKey = @"initialURL";

@implementation RNROpenSessionRequest

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithInitialURL:(NSURL *)initialURL
{
    NSParameterAssert(initialURL != nil);

    self = [super init];
    if (self) {
        _initialURL = [initialURL copy];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    NSURL *initialURL = [coder decodeObjectOfClass:[NSURL class]
                                            forKey:RNROpenSessionRequestInitialURLKey];
    if (![initialURL isKindOfClass:[NSURL class]]) {
        return nil;
    }

    return [self initWithInitialURL:initialURL];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:self.initialURL forKey:RNROpenSessionRequestInitialURLKey];
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    return self;
}

@end
