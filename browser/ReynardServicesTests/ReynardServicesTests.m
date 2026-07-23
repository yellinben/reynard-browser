#import <XCTest/XCTest.h>
#import <ReynardProtocol/ReynardProtocol.h>

#import "RNRMockHostConnection.h"
#import "RNRSessionCoordinator.h"

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
