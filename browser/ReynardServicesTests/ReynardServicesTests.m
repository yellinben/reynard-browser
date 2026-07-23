#import <XCTest/XCTest.h>
#import <ReynardProtocol/ReynardProtocol.h>

#import "RNRMockHostConnection.h"
#import "RNRMockMessageTransport.h"
#import "RNRCFMessagePortHostConnection.h"
#import "RNRCFMessagePortTransport.h"
#import "RNRSessionCoordinator.h"

static CFDataRef RNRTestMessagePortCallback(CFMessagePortRef local,
                                            SInt32 messageIdentifier,
                                            CFDataRef data,
                                            void *info)
{
    (void)local;
    (void)data;
    (void)info;
    NSDictionary *response = @{
        RNRRuntimeWireNegotiatedVersionKey: @(messageIdentifier),
    };
    NSData *responseData = [NSPropertyListSerialization dataWithPropertyList:response
                                                                      format:NSPropertyListBinaryFormat_v1_0
                                                                     options:0
                                                                       error:nil];
    return CFBridgingRetain(responseData);
}

@interface ReynardServicesTests : XCTestCase
@end

@implementation ReynardServicesTests

- (void)testProtocolConstantsHaveStableValues {
    XCTAssertEqualObjects(RNRProtocolErrorDomain, @"in.benyell.ReynardProtocol");
    XCTAssertEqual(RNRProtocolVersionInvalid, 0);
    XCTAssertEqual(RNRProtocolVersionMinimumCompatible, 1);
    XCTAssertEqual(RNRProtocolVersionCurrent, 1);

    XCTAssertEqual(RNRProtocolErrorUnknown, 1);
    XCTAssertEqual(RNRProtocolErrorIncompatibleVersion, 2);
    XCTAssertEqual(RNRProtocolErrorInvalidRequest, 3);
    XCTAssertEqual(RNRProtocolErrorHostUnavailable, 4);
    XCTAssertEqual(RNRProtocolErrorMissingSession, 5);
    XCTAssertEqual(RNRProtocolErrorConnectionInterrupted, 6);
    XCTAssertEqual(RNRProtocolErrorSessionTerminated, 7);

    XCTAssertEqualObjects(RNRRuntimeServiceName, @"in.benyell.reynard.runtime.stage1");
    XCTAssertEqual(RNRRuntimeMessageNegotiateProtocol, 1);
    XCTAssertEqual(RNRRuntimeMessageOpenSession, 2);
    XCTAssertEqual(RNRRuntimeMessageCloseSession, 3);
}

- (void)testMessagePortConnectionEncodesNegotiation
{
    RNRMockMessageTransport *transport = [[RNRMockMessageTransport alloc] init];
    transport.response = @{RNRRuntimeWireNegotiatedVersionKey: @(RNRProtocolVersionCurrent)};
    RNRCFMessagePortHostConnection *connection =
        [[RNRCFMessagePortHostConnection alloc] initWithTransport:transport];

    __block RNRProtocolVersion version = RNRProtocolVersionInvalid;
    __block NSError *negotiationError = nil;
    [connection negotiateProtocolVersionWithClientMinimumVersion:RNRProtocolVersionMinimumCompatible
                                            clientMaximumVersion:RNRProtocolVersionCurrent
                                                      completion:^(RNRProtocolVersion negotiatedVersion, NSError *error) {
        version = negotiatedVersion;
        negotiationError = error;
    }];

    XCTAssertNil(negotiationError);
    XCTAssertEqual(version, RNRProtocolVersionCurrent);
    XCTAssertEqual(transport.receivedMessageIdentifier, RNRRuntimeMessageNegotiateProtocol);
    XCTAssertEqualObjects(
        transport.receivedPayload[RNRRuntimeWireClientMinimumVersionKey],
        @(RNRProtocolVersionMinimumCompatible)
    );
    XCTAssertEqualObjects(
        transport.receivedPayload[RNRRuntimeWireClientMaximumVersionKey],
        @(RNRProtocolVersionCurrent)
    );
}

- (void)testMessagePortConnectionForwardsSecureOpenAndCloseArchives
{
    RNRMockMessageTransport *transport = [[RNRMockMessageTransport alloc] init];
    RNRCFMessagePortHostConnection *connection =
        [[RNRCFMessagePortHostConnection alloc] initWithTransport:transport];
    RNROpenSessionRequest *request = [[RNROpenSessionRequest alloc]
        initWithInitialURL:[NSURL URLWithString:@"https://example.com/runtime"]];
    RNRSessionIdentifier *hostIdentifier = [[RNRSessionIdentifier alloc] init];
    NSData *identifierArchive = [NSKeyedArchiver archivedDataWithRootObject:hostIdentifier
                                                      requiringSecureCoding:YES
                                                                      error:nil];
    transport.response = @{RNRRuntimeWireArchivedObjectKey: identifierArchive};

    __block RNRSessionIdentifier *receivedIdentifier = nil;
    [connection openSessionWithRequest:request completion:^(RNRSessionIdentifier *identifier, NSError *error) {
        XCTAssertNil(error);
        receivedIdentifier = identifier;
    }];

    XCTAssertEqual(transport.receivedMessageIdentifier, RNRRuntimeMessageOpenSession);
    NSData *requestArchive = transport.receivedPayload[RNRRuntimeWireArchivedObjectKey];
    RNROpenSessionRequest *decodedRequest = [NSKeyedUnarchiver
        unarchivedObjectOfClass:RNROpenSessionRequest.class
        fromData:requestArchive
        error:nil];
    XCTAssertEqualObjects(decodedRequest.initialURL, request.initialURL);
    XCTAssertEqualObjects(receivedIdentifier, hostIdentifier);

    transport.response = @{};
    [connection closeSessionWithIdentifier:receivedIdentifier completion:^(NSError *error) {
        XCTAssertNil(error);
    }];

    XCTAssertEqual(transport.receivedMessageIdentifier, RNRRuntimeMessageCloseSession);
    NSData *closeArchive = transport.receivedPayload[RNRRuntimeWireArchivedObjectKey];
    RNRSessionIdentifier *decodedIdentifier = [NSKeyedUnarchiver
        unarchivedObjectOfClass:RNRSessionIdentifier.class
        fromData:closeArchive
        error:nil];
    XCTAssertEqualObjects(decodedIdentifier, hostIdentifier);
}

- (void)testMessagePortConnectionMapsHostErrorCodes
{
    RNRMockMessageTransport *transport = [[RNRMockMessageTransport alloc] init];
    transport.response = @{RNRRuntimeWireErrorCodeKey: @(RNRProtocolErrorIncompatibleVersion)};
    RNRCFMessagePortHostConnection *connection =
        [[RNRCFMessagePortHostConnection alloc] initWithTransport:transport];

    __block NSError *negotiationError = nil;
    [connection negotiateProtocolVersionWithClientMinimumVersion:2
                                            clientMaximumVersion:2
                                                      completion:^(RNRProtocolVersion negotiatedVersion, NSError *error) {
        XCTAssertEqual(negotiatedVersion, RNRProtocolVersionInvalid);
        negotiationError = error;
    }];

    XCTAssertEqualObjects(negotiationError.domain, RNRProtocolErrorDomain);
    XCTAssertEqual(negotiationError.code, RNRProtocolErrorIncompatibleVersion);
}

- (void)testCFMessagePortTransportRoundTripDoesNotActivateHost
{
    NSString *serviceName = [NSString stringWithFormat:@"in.benyell.reynard.tests.%@", NSUUID.UUID.UUIDString];
    CFMessagePortContext context = {0, NULL, NULL, NULL, NULL};
    CFMessagePortRef localPort = CFMessagePortCreateLocal(
        kCFAllocatorDefault,
        (__bridge CFStringRef)serviceName,
        RNRTestMessagePortCallback,
        &context,
        NULL
    );
    XCTAssertNotEqual(localPort, NULL);
    CFRunLoopSourceRef source = CFMessagePortCreateRunLoopSource(kCFAllocatorDefault, localPort, 0);
    XCTAssertNotEqual(source, NULL);
    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);

    __block BOOL activatedHost = NO;
    RNRCFMessagePortTransport *transport = [[RNRCFMessagePortTransport alloc]
        initWithServiceName:serviceName
        activationHandler:^{
            activatedHost = YES;
        }];
    XCTestExpectation *reply = [self expectationWithDescription:@"message-port reply"];
    [transport sendMessageIdentifier:RNRRuntimeMessageNegotiateProtocol
                             payload:@{RNRRuntimeWireClientMinimumVersionKey: @(1)}
                          completion:^(NSDictionary<NSString *,id> *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(
            response[RNRRuntimeWireNegotiatedVersionKey],
            @(RNRRuntimeMessageNegotiateProtocol)
        );
        [reply fulfill];
    }];

    [self waitForExpectations:@[reply] timeout:2.0];
    XCTAssertFalse(activatedHost);
    [transport invalidate];
    CFRunLoopRemoveSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
    CFRunLoopSourceInvalidate(source);
    CFRelease(source);
    CFMessagePortInvalidate(localPort);
    CFRelease(localPort);
}

- (void)testSessionIdentifierHasValueSemanticsAndSupportsSecureCoding {
    RNRSessionIdentifier *identifier = [[RNRSessionIdentifier alloc] init];
    RNRSessionIdentifier *copiedIdentifier = [identifier copy];
    NSError *archiveError = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:identifier
                                        requiringSecureCoding:YES
                                                        error:&archiveError];
    XCTAssertNotNil(data);
    XCTAssertNil(archiveError);

    NSError *unarchiveError = nil;
    RNRSessionIdentifier *decodedIdentifier =
        [NSKeyedUnarchiver unarchivedObjectOfClass:RNRSessionIdentifier.class
                                          fromData:data
                                             error:&unarchiveError];

    XCTAssertNil(unarchiveError);
    XCTAssertEqualObjects(identifier, copiedIdentifier);
    XCTAssertEqualObjects(identifier, decodedIdentifier);
    XCTAssertEqual(identifier.hash, decodedIdentifier.hash);
}

- (void)testOpenRequestSupportsSecureCoding {
    NSURL *URL = [NSURL URLWithString:@"https://example.com/path"];
    RNROpenSessionRequest *request = [[RNROpenSessionRequest alloc] initWithInitialURL:URL];
    NSError *archiveError = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:request
                                        requiringSecureCoding:YES
                                                        error:&archiveError];
    XCTAssertNotNil(data);
    XCTAssertNil(archiveError);

    NSError *unarchiveError = nil;
    RNROpenSessionRequest *decodedRequest =
        [NSKeyedUnarchiver unarchivedObjectOfClass:RNROpenSessionRequest.class
                                          fromData:data
                                             error:&unarchiveError];

    XCTAssertNil(unarchiveError);
    XCTAssertEqualObjects(decodedRequest.initialURL, URL);
}

- (void)testOpenRequestRejectsMalformedArchive {
    NSData *malformedData = [@"not an archive" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    RNROpenSessionRequest *request =
        [NSKeyedUnarchiver unarchivedObjectOfClass:RNROpenSessionRequest.class
                                          fromData:malformedData
                                             error:&error];

    XCTAssertNil(request);
    XCTAssertNotNil(error);
}

- (void)testCompatibleNegotiationForwardsOpenAndCloseExactlyOnce {
    RNRMockHostConnection *connection = [[RNRMockHostConnection alloc] init];
    RNRSessionCoordinator *coordinator =
        [[RNRSessionCoordinator alloc] initWithHostConnection:connection];
    RNROpenSessionRequest *request =
        [[RNROpenSessionRequest alloc] initWithInitialURL:[NSURL URLWithString:@"https://example.com"]];

    __block RNRSessionIdentifier *openedIdentifier = nil;
    __block NSError *openError = nil;
    [coordinator openSessionWithRequest:request completion:^(RNRSessionIdentifier *identifier, NSError *error) {
        openedIdentifier = identifier;
        openError = error;
    }];

    XCTAssertNil(openError);
    XCTAssertEqual(connection.negotiationCount, 1U);
    XCTAssertEqual(connection.receivedMinimumVersion, RNRProtocolVersionMinimumCompatible);
    XCTAssertEqual(connection.receivedMaximumVersion, RNRProtocolVersionCurrent);
    XCTAssertEqual(connection.openCount, 1U);
    XCTAssertEqual(connection.receivedOpenRequest, request);
    XCTAssertEqualObjects(openedIdentifier, connection.openSessionIdentifier);
    XCTAssertTrue([coordinator.activeSessionIdentifiers containsObject:openedIdentifier]);

    __block NSError *closeError = nil;
    [coordinator closeSessionWithIdentifier:openedIdentifier completion:^(NSError *error) {
        closeError = error;
    }];

    XCTAssertNil(closeError);
    XCTAssertEqual(connection.closeCount, 1U);
    XCTAssertEqualObjects(connection.receivedCloseIdentifier, openedIdentifier);
    XCTAssertFalse([coordinator.activeSessionIdentifiers containsObject:openedIdentifier]);
}

- (void)testIncompatibleNegotiationDoesNotOpenSession {
    RNRMockHostConnection *connection = [[RNRMockHostConnection alloc] init];
    connection.negotiatedVersion = RNRProtocolVersionInvalid;
    RNRSessionCoordinator *coordinator =
        [[RNRSessionCoordinator alloc] initWithHostConnection:connection];
    RNROpenSessionRequest *request =
        [[RNROpenSessionRequest alloc] initWithInitialURL:[NSURL URLWithString:@"https://example.com"]];

    __block RNRSessionIdentifier *openedIdentifier = nil;
    __block NSError *openError = nil;
    [coordinator openSessionWithRequest:request completion:^(RNRSessionIdentifier *identifier, NSError *error) {
        openedIdentifier = identifier;
        openError = error;
    }];

    XCTAssertNil(openedIdentifier);
    XCTAssertEqualObjects(openError.domain, RNRProtocolErrorDomain);
    XCTAssertEqual(openError.code, RNRProtocolErrorIncompatibleVersion);
    XCTAssertEqual(connection.openCount, 0U);
    XCTAssertEqual(coordinator.activeSessionIdentifiers.count, 0U);
}

- (void)testOpenFailureDoesNotCreateSession {
    RNRMockHostConnection *connection = [[RNRMockHostConnection alloc] init];
    connection.openError = [NSError errorWithDomain:RNRProtocolErrorDomain
                                               code:RNRProtocolErrorHostUnavailable
                                           userInfo:nil];
    RNRSessionCoordinator *coordinator =
        [[RNRSessionCoordinator alloc] initWithHostConnection:connection];
    RNROpenSessionRequest *request =
        [[RNROpenSessionRequest alloc] initWithInitialURL:[NSURL URLWithString:@"https://example.com"]];

    __block RNRSessionIdentifier *openedIdentifier = nil;
    __block NSError *openError = nil;
    [coordinator openSessionWithRequest:request completion:^(RNRSessionIdentifier *identifier, NSError *error) {
        openedIdentifier = identifier;
        openError = error;
    }];

    XCTAssertNil(openedIdentifier);
    XCTAssertEqual(openError, connection.openError);
    XCTAssertEqual(coordinator.activeSessionIdentifiers.count, 0U);
}

- (void)testHostClosureAndConnectionInvalidationCleanUpSessions {
    RNRMockHostConnection *connection = [[RNRMockHostConnection alloc] init];
    RNRSessionCoordinator *coordinator =
        [[RNRSessionCoordinator alloc] initWithHostConnection:connection];
    RNROpenSessionRequest *request =
        [[RNROpenSessionRequest alloc] initWithInitialURL:[NSURL URLWithString:@"https://example.com"]];

    __block RNRSessionIdentifier *firstIdentifier = nil;
    [coordinator openSessionWithRequest:request completion:^(RNRSessionIdentifier *identifier, NSError *error) {
        firstIdentifier = identifier;
    }];
    [connection simulateHostClosureForSessionIdentifier:firstIdentifier error:nil];
    XCTAssertEqual(coordinator.activeSessionIdentifiers.count, 0U);

    connection.openSessionIdentifier = [[RNRSessionIdentifier alloc] init];
    __block RNRSessionIdentifier *secondIdentifier = nil;
    [coordinator openSessionWithRequest:request completion:^(RNRSessionIdentifier *identifier, NSError *error) {
        secondIdentifier = identifier;
    }];
    XCTAssertTrue([coordinator.activeSessionIdentifiers containsObject:secondIdentifier]);

    NSError *interrupted = [NSError errorWithDomain:RNRProtocolErrorDomain
                                               code:RNRProtocolErrorConnectionInterrupted
                                           userInfo:nil];
    [connection simulateInvalidationWithError:interrupted];

    XCTAssertFalse(coordinator.isReady);
    XCTAssertEqual(coordinator.activeSessionIdentifiers.count, 0U);
}

@end
