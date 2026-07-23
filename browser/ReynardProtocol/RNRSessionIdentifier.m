#import "RNRSessionIdentifier.h"

static NSString *const RNRSessionIdentifierUUIDKey = @"uuid";

@interface RNRSessionIdentifier ()

@property (nonatomic, readonly) NSUUID *UUID;

- (instancetype)initWithUUID:(NSUUID *)UUID NS_DESIGNATED_INITIALIZER;

@end

@implementation RNRSessionIdentifier

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)init
{
    return [self initWithUUID:[NSUUID UUID]];
}

- (instancetype)initWithUUID:(NSUUID *)UUID
{
    self = [super init];
    if (self) {
        _UUID = [UUID copy];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    NSUUID *UUID = [coder decodeObjectOfClass:[NSUUID class]
                                       forKey:RNRSessionIdentifierUUIDKey];
    if (![UUID isKindOfClass:[NSUUID class]]) {
        return nil;
    }

    return [self initWithUUID:UUID];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:self.UUID forKey:RNRSessionIdentifierUUIDKey];
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    return self;
}

- (BOOL)isEqual:(id)object
{
    if (object == self) {
        return YES;
    }
    if (![object isKindOfClass:[RNRSessionIdentifier class]]) {
        return NO;
    }

    RNRSessionIdentifier *otherIdentifier = object;
    return [self.UUID isEqual:otherIdentifier.UUID];
}

- (NSUInteger)hash
{
    return self.UUID.hash;
}

@end
