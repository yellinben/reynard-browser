#import "RNRIPCSmokeViewController.h"

#import <ReynardProtocol/ReynardProtocol.h>

#import "RNRCFMessagePortHostConnection.h"
#import "RNRCFMessagePortTransport.h"
#import "RNRIPCSmokeState.h"

#import <unistd.h>

static NSString *RNRIPCSmokeTransportEventName(RNRMessageTransportDiagnosticEvent event)
{
    switch (event) {
        case RNRMessageTransportDiagnosticEventDiscoveryAttempt:
            return @"discovery-attempt";
        case RNRMessageTransportDiagnosticEventActivationRequested:
            return @"activation-requested";
        case RNRMessageTransportDiagnosticEventPortDiscovered:
            return @"port-discovered";
        case RNRMessageTransportDiagnosticEventRequestStarted:
            return @"request-started";
        case RNRMessageTransportDiagnosticEventRequestCompleted:
            return @"request-completed";
        case RNRMessageTransportDiagnosticEventInvalidated:
            return @"invalidated";
        case RNRMessageTransportDiagnosticEventTimeout:
            return @"timeout";
    }
    return @"unknown";
}

static NSTimeInterval RNRIPCSmokeMonotonicTime(void)
{
    return NSProcessInfo.processInfo.systemUptime;
}

static BOOL RNRIPCSmokeErrorMayHideHostEffect(NSError *error)
{
    return [error.domain isEqualToString:RNRProtocolErrorDomain] &&
        (error.code == RNRProtocolErrorHostUnavailable ||
         error.code == RNRProtocolErrorConnectionInterrupted);
}

@interface RNRIPCSmokeViewController ()

@property (nonatomic, strong) RNRCFMessagePortTransport *transport;
@property (nonatomic, strong) RNRCFMessagePortHostConnection *connection;
@property (nonatomic, strong, nullable) RNRSessionIdentifier *activeSessionIdentifier;
@property (nonatomic, strong) RNRIPCSmokeState *state;
@property (nonatomic) BOOL clientInvalidated;
@property (nonatomic) BOOL requestStartedForCurrentOperation;

@property (nonatomic, strong) UITextField *URLField;
@property (nonatomic, strong) UILabel *resultLabel;
@property (nonatomic, strong) UITextView *diagnosticsView;
@property (nonatomic, strong) UIButton *negotiateButton;
@property (nonatomic, strong) UIButton *openButton;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *incompatibleButton;
@property (nonatomic, strong) UIButton *invalidURLButton;
@property (nonatomic, strong) UIButton *malformedButton;
@property (nonatomic, strong) UIButton *unknownCloseButton;
@property (nonatomic, strong) UIButton *probeButton;
@property (nonatomic, strong) UIButton *invalidateButton;
@property (nonatomic, strong) UIButton *resetRetryButton;

@end

@implementation RNRIPCSmokeViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Reynard IPC Smoke";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.state = [[RNRIPCSmokeState alloc] init];
    [self configureConnectionWithActivationEnabled:YES];
    [self buildInterface];
    self.resultLabel.text = self.state.resultSummary;
    [self appendDiagnostic:@"ready pid=%d transport=Stage-1 client_identity=unavailable",
                           getpid()];
    [self updateControls];
}

- (void)configureConnectionWithActivationEnabled:(BOOL)activationEnabled
{
    __weak typeof(self) weakSelf = self;
    RNRHostActivationHandler activationHandler = activationEnabled ? ^{
        RNRActivateStageOneHost();
    } : ^{};
    self.transport = [[RNRCFMessagePortTransport alloc]
        initWithServiceName:RNRRuntimeServiceName
        activationHandler:activationHandler
        diagnosticHandler:^(RNRMessageTransportDiagnosticEvent event,
                            RNRRuntimeMessageIdentifier messageIdentifier,
                            NSUInteger attemptNumber,
                            NSUInteger maximumAttemptCount,
                            NSTimeInterval duration,
                            NSError *error) {
            [weakSelf recordTransportEvent:event
                         messageIdentifier:messageIdentifier
                             attemptNumber:attemptNumber
                       maximumAttemptCount:maximumAttemptCount
                                  duration:duration
                                     error:error
                      activationSuppressed:!activationEnabled];
        }];
    self.connection = [[RNRCFMessagePortHostConnection alloc] initWithTransport:self.transport];
    self.clientInvalidated = NO;
}

- (void)buildInterface
{
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scrollView];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:stack];

    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor],
        [scrollView.topAnchor constraintEqualToAnchor:safeArea.topAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.leadingAnchor constant:16.0],
        [stack.trailingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.trailingAnchor constant:-16.0],
        [stack.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor constant:16.0],
        [stack.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor constant:-24.0],
        [stack.widthAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor constant:-32.0],
    ]];

    UILabel *warning = [self labelWithText:
        @"Development-only Stage 1 harness. The transport does not authenticate or identify callers. Logical sessions are not identity-bound, and no logical session is connected to Gecko state. Host death is observed only by a later request."];
    warning.textColor = UIColor.systemRedColor;
    warning.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];

    self.URLField = [[UITextField alloc] init];
    self.URLField.borderStyle = UITextBorderStyleRoundedRect;
    self.URLField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.URLField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.URLField.keyboardType = UIKeyboardTypeURL;
    self.URLField.text = @"https://example.com/";
    self.URLField.accessibilityLabel = @"HTTP or HTTPS URL";
    [stack addArrangedSubview:self.URLField];

    self.negotiateButton = [self buttonWithTitle:@"Negotiate 1...1"
                                          action:@selector(negotiateCompatible)];
    self.openButton = [self buttonWithTitle:@"Open HTTP(S)"
                                     action:@selector(openDefaultURL)];
    self.closeButton = [self buttonWithTitle:@"Close Active Session"
                                      action:@selector(closeActiveSession)];
    self.incompatibleButton = [self buttonWithTitle:@"Negotiate Incompatible"
                                             action:@selector(negotiateIncompatible)];
    self.invalidURLButton = [self buttonWithTitle:@"Open Invalid Scheme"
                                           action:@selector(openInvalidURL)];
    self.malformedButton = [self buttonWithTitle:@"Send Malformed Open"
                                          action:@selector(sendMalformedOpen)];
    self.unknownCloseButton = [self buttonWithTitle:@"Close Unknown Session"
                                             action:@selector(closeUnknownSession)];
    self.probeButton = [self buttonWithTitle:@"Probe Host Without Activation"
                                      action:@selector(probeWithoutActivation)];
    self.invalidateButton = [self buttonWithTitle:@"Invalidate Client Connection"
                                           action:@selector(invalidateClientConnection)];
    self.resetRetryButton = [self buttonWithTitle:@"Reset Connection + Retry Negotiation"
                                           action:@selector(resetConnectionAndRetry)];

    NSArray<UIButton *> *buttons = @[
        self.negotiateButton,
        self.openButton,
        self.closeButton,
        self.incompatibleButton,
        self.invalidURLButton,
        self.malformedButton,
        self.unknownCloseButton,
        self.probeButton,
        self.invalidateButton,
        self.resetRetryButton,
    ];
    NSArray<NSString *> *descriptions = @[
        @"Request the highest shared Stage 1 protocol version.",
        @"Create one logical session for the URL; this does not navigate Gecko.",
        @"Remove the current opaque logical session from the host registry.",
        @"Request version 2...2; expect version 0 and protocol error 2.",
        @"Send a non-HTTP(S) request; expect invalid-request error 3.",
        @"Send an open message without its archive; expect error 3.",
        @"Close a fresh opaque identifier; expect missing-session error 5.",
        @"Run bounded discovery with host activation suppressed.",
        @"Invalidate this client transport; an active session becomes indeterminate.",
        @"Retry on a fresh transport. Active sessions must be closed; indeterminate state requires confirming the host restarted.",
    ];
    [buttons enumerateObjectsUsingBlock:^(UIButton *button, NSUInteger index, BOOL *stop) {
        (void)stop;
        [stack addArrangedSubview:[self actionContainerWithButton:button
                                                      description:descriptions[index]]];
    }];

    UILabel *resultTitle = [self labelWithText:@"Last result"];
    resultTitle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    [stack addArrangedSubview:resultTitle];

    self.resultLabel = [self labelWithText:@""];
    self.resultLabel.font = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightRegular];
    self.resultLabel.accessibilityIdentifier = @"ipc-smoke-result";
    [stack addArrangedSubview:self.resultLabel];

    UILabel *diagnosticTitle = [self labelWithText:@"Transport observations (no URLs or payloads)"];
    diagnosticTitle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    [stack addArrangedSubview:diagnosticTitle];

    self.diagnosticsView = [[UITextView alloc] init];
    self.diagnosticsView.editable = NO;
    self.diagnosticsView.scrollEnabled = YES;
    self.diagnosticsView.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.diagnosticsView.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular];
    self.diagnosticsView.accessibilityIdentifier = @"ipc-smoke-diagnostics";
    [self.diagnosticsView.heightAnchor constraintEqualToConstant:300.0].active = YES;
    [stack addArrangedSubview:self.diagnosticsView];

    UILabel *warningTitle = [self labelWithText:@"Security boundary"];
    warningTitle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    warningTitle.textColor = UIColor.systemRedColor;
    [stack addArrangedSubview:warningTitle];
    [stack addArrangedSubview:warning];
}

- (UILabel *)labelWithText:(NSString *)text
{
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.numberOfLines = 0;
    return label;
}

- (UIButton *)buttonWithTitle:(NSString *)title action:(SEL)action
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    button.contentEdgeInsets = UIEdgeInsetsMake(8.0, 10.0, 8.0, 10.0);
    button.layer.cornerRadius = 8.0;
    button.backgroundColor = UIColor.secondarySystemBackgroundColor;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIView *)actionContainerWithButton:(UIButton *)button description:(NSString *)description
{
    UIStackView *container = [[UIStackView alloc] init];
    container.axis = UILayoutConstraintAxisVertical;
    container.spacing = 3.0;
    [container addArrangedSubview:button];

    UILabel *label = [self labelWithText:description];
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    label.textColor = UIColor.secondaryLabelColor;
    [container addArrangedSubview:label];
    return container;
}

- (BOOL)beginOperation:(NSString *)operationName
{
    if (![self.state beginOperationNamed:operationName]) {
        [self appendDiagnostic:@"operation rejected reason=single-flight-busy"];
        return NO;
    }
    self.requestStartedForCurrentOperation = NO;
    [self appendDiagnostic:@"operation started id=%@ operation=%@",
                           self.state.operationIdentifier.UUIDString,
                           operationName];
    [self updateControls];
    return YES;
}

- (void)finishOperationStartedAt:(NSTimeInterval)startedAt
                negotiatedVersion:(RNRProtocolVersion)negotiatedVersion
                     sessionState:(RNRIPCSmokeSessionState)sessionState
                            error:(NSError *)error
{
    NSTimeInterval duration = RNRIPCSmokeMonotonicTime() - startedAt;
    [self.state finishOperationWithDuration:duration
                          negotiatedVersion:negotiatedVersion
                               sessionState:sessionState
                                      error:error];
    self.resultLabel.text = self.state.resultSummary;
    [self appendDiagnostic:@"operation finished id=%@ operation=%@ duration_ms=%.1f error_domain=%@ error_code=%ld session_state=%@",
                           self.state.operationIdentifier.UUIDString,
                           self.state.operationName,
                           duration * 1000.0,
                           error.domain ?: @"none",
                           (long)error.code,
                           RNRIPCSmokeSessionStateName(sessionState)];
    [self updateControls];
}

- (void)negotiateCompatible
{
    if (![self beginOperation:@"negotiate-compatible"]) {
        return;
    }
    NSTimeInterval startedAt = RNRIPCSmokeMonotonicTime();
    RNRIPCSmokeSessionState sessionState = self.state.sessionState;
    [self.connection negotiateProtocolVersionWithClientMinimumVersion:RNRProtocolVersionMinimumCompatible
                                                  clientMaximumVersion:RNRProtocolVersionCurrent
                                                            completion:^(RNRProtocolVersion version, NSError *error) {
        [self finishOperationStartedAt:startedAt
                      negotiatedVersion:version
                           sessionState:sessionState
                                  error:error];
    }];
}

- (void)negotiateIncompatible
{
    if (![self beginOperation:@"negotiate-incompatible"]) {
        return;
    }
    NSTimeInterval startedAt = RNRIPCSmokeMonotonicTime();
    RNRProtocolVersion unsupportedVersion = RNRProtocolVersionCurrent + 1;
    RNRIPCSmokeSessionState sessionState = self.state.sessionState;
    [self.connection negotiateProtocolVersionWithClientMinimumVersion:unsupportedVersion
                                                  clientMaximumVersion:unsupportedVersion
                                                            completion:^(RNRProtocolVersion version, NSError *error) {
        [self finishOperationStartedAt:startedAt
                      negotiatedVersion:version
                           sessionState:sessionState
                                  error:error];
    }];
}

- (void)openDefaultURL
{
    NSURL *URL = [NSURL URLWithString:self.URLField.text ?: @""];
    if (!URL) {
        self.resultLabel.text = @"Invalid local URL input; no request was sent.";
        return;
    }
    [self openURL:URL operationName:@"open-http" expectedInvalid:NO];
}

- (void)openInvalidURL
{
    NSURL *URL = [NSURL URLWithString:@"reynard-smoke://invalid/"];
    [self openURL:URL operationName:@"open-invalid-scheme" expectedInvalid:YES];
}

- (void)openURL:(NSURL *)URL operationName:(NSString *)operationName expectedInvalid:(BOOL)expectedInvalid
{
    if (![self beginOperation:operationName]) {
        return;
    }
    NSTimeInterval startedAt = RNRIPCSmokeMonotonicTime();
    RNROpenSessionRequest *request = [[RNROpenSessionRequest alloc] initWithInitialURL:URL];
    [self.connection openSessionWithRequest:request
                                  completion:^(RNRSessionIdentifier *identifier, NSError *error) {
        RNRIPCSmokeSessionState sessionState;
        if (identifier && !error) {
            self.activeSessionIdentifier = identifier;
            sessionState = RNRIPCSmokeSessionStateActive;
        } else if (expectedInvalid || !RNRIPCSmokeErrorMayHideHostEffect(error) ||
                   !self.requestStartedForCurrentOperation) {
            sessionState = self.state.sessionState;
        } else {
            sessionState = RNRIPCSmokeSessionStateIndeterminate;
        }
        [self finishOperationStartedAt:startedAt
                      negotiatedVersion:self.state.negotiatedVersion
                           sessionState:sessionState
                                  error:error];
    }];
}

- (void)closeActiveSession
{
    RNRSessionIdentifier *identifier = self.activeSessionIdentifier;
    if (!identifier || ![self beginOperation:@"close-active"]) {
        return;
    }
    NSTimeInterval startedAt = RNRIPCSmokeMonotonicTime();
    [self.connection closeSessionWithIdentifier:identifier completion:^(NSError *error) {
        RNRIPCSmokeSessionState state = RNRIPCSmokeSessionStateActive;
        if (!error || error.code == RNRProtocolErrorMissingSession) {
            self.activeSessionIdentifier = nil;
            state = RNRIPCSmokeSessionStateNone;
        } else if (RNRIPCSmokeErrorMayHideHostEffect(error) &&
                   self.requestStartedForCurrentOperation) {
            state = RNRIPCSmokeSessionStateIndeterminate;
        }
        [self finishOperationStartedAt:startedAt
                      negotiatedVersion:self.state.negotiatedVersion
                           sessionState:state
                                  error:error];
    }];
}

- (void)closeUnknownSession
{
    if (![self beginOperation:@"close-unknown"]) {
        return;
    }
    NSTimeInterval startedAt = RNRIPCSmokeMonotonicTime();
    RNRSessionIdentifier *identifier = [[RNRSessionIdentifier alloc] init];
    RNRIPCSmokeSessionState sessionState = self.state.sessionState;
    [self.connection closeSessionWithIdentifier:identifier completion:^(NSError *error) {
        [self finishOperationStartedAt:startedAt
                      negotiatedVersion:self.state.negotiatedVersion
                           sessionState:sessionState
                                  error:error];
    }];
}

- (void)sendMalformedOpen
{
    if (![self beginOperation:@"open-malformed"]) {
        return;
    }
    NSTimeInterval startedAt = RNRIPCSmokeMonotonicTime();
    RNRIPCSmokeSessionState sessionState = self.state.sessionState;
    [self.transport sendMessageIdentifier:RNRRuntimeMessageOpenSession
                                   payload:@{}
                                completion:^(NSDictionary<NSString *,id> *response, NSError *transportError) {
        NSNumber *code = response[RNRRuntimeWireErrorCodeKey];
        NSError *error = transportError;
        if (!error && [code isKindOfClass:NSNumber.class]) {
            error = [NSError errorWithDomain:RNRProtocolErrorDomain
                                        code:code.integerValue
                                    userInfo:nil];
        }
        if (!error) {
            error = [NSError errorWithDomain:RNRProtocolErrorDomain
                                        code:RNRProtocolErrorInvalidRequest
                                    userInfo:nil];
        }
        [self finishOperationStartedAt:startedAt
                      negotiatedVersion:self.state.negotiatedVersion
                           sessionState:sessionState
                                  error:error];
    }];
}

- (void)probeWithoutActivation
{
    if (![self beginOperation:@"probe-no-activation"]) {
        return;
    }
    NSTimeInterval startedAt = RNRIPCSmokeMonotonicTime();
    RNRIPCSmokeSessionState sessionState = self.state.sessionState;
    __weak typeof(self) weakSelf = self;
    RNRCFMessagePortTransport *transport = [[RNRCFMessagePortTransport alloc]
        initWithServiceName:RNRRuntimeServiceName
        activationHandler:^{}
        diagnosticHandler:^(RNRMessageTransportDiagnosticEvent event,
                            RNRRuntimeMessageIdentifier messageIdentifier,
                            NSUInteger attemptNumber,
                            NSUInteger maximumAttemptCount,
                            NSTimeInterval duration,
                            NSError *error) {
            [weakSelf recordTransportEvent:event
                         messageIdentifier:messageIdentifier
                             attemptNumber:attemptNumber
                       maximumAttemptCount:maximumAttemptCount
                                  duration:duration
                                     error:error
                      activationSuppressed:YES];
        }];
    RNRCFMessagePortHostConnection *connection = [[RNRCFMessagePortHostConnection alloc]
        initWithTransport:transport];
    [connection negotiateProtocolVersionWithClientMinimumVersion:RNRProtocolVersionMinimumCompatible
                                             clientMaximumVersion:RNRProtocolVersionCurrent
                                                       completion:^(RNRProtocolVersion version, NSError *error) {
        (void)connection;
        [self finishOperationStartedAt:startedAt
                      negotiatedVersion:version
                           sessionState:sessionState
                                  error:error];
    }];
}

- (void)invalidateClientConnection
{
    if (![self beginOperation:@"invalidate-client"]) {
        return;
    }
    NSTimeInterval startedAt = RNRIPCSmokeMonotonicTime();
    BOOL hadActiveSession = self.activeSessionIdentifier != nil;
    [self.connection invalidate];
    self.clientInvalidated = YES;
    self.activeSessionIdentifier = nil;
    NSError *error = [NSError errorWithDomain:RNRProtocolErrorDomain
                                         code:RNRProtocolErrorConnectionInterrupted
                                     userInfo:nil];
    [self finishOperationStartedAt:startedAt
                  negotiatedVersion:RNRProtocolVersionInvalid
                       sessionState:hadActiveSession ? RNRIPCSmokeSessionStateIndeterminate
                                                     : RNRIPCSmokeSessionStateNone
                              error:error];
}

- (void)resetConnectionAndRetry
{
    if (self.state.isBusy || self.state.sessionState == RNRIPCSmokeSessionStateActive) {
        return;
    }
    if (self.state.sessionState == RNRIPCSmokeSessionStateIndeterminate) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Confirm Host Restart"
            message:@"Continue only after Reynard.app was terminated and restarted. This discards local opaque session state; it does not close a live host session."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                  style:UIAlertActionStyleCancel
                                                handler:nil]];
        __weak typeof(self) weakSelf = self;
        [alert addAction:[UIAlertAction actionWithTitle:@"Host Restarted"
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(__unused UIAlertAction *action) {
            [weakSelf resetConnectionAndRetryConfirmed];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    [self resetConnectionAndRetryConfirmed];
}

- (void)resetConnectionAndRetryConfirmed
{
    [self.connection invalidate];
    self.activeSessionIdentifier = nil;
    [self.state reset];
    [self configureConnectionWithActivationEnabled:YES];
    [self negotiateCompatibleAfterReset];
}

- (void)negotiateCompatibleAfterReset
{
    if (![self beginOperation:@"reset-and-negotiate"]) {
        return;
    }
    NSTimeInterval startedAt = RNRIPCSmokeMonotonicTime();
    [self.connection negotiateProtocolVersionWithClientMinimumVersion:RNRProtocolVersionMinimumCompatible
                                                  clientMaximumVersion:RNRProtocolVersionCurrent
                                                            completion:^(RNRProtocolVersion version, NSError *error) {
        [self finishOperationStartedAt:startedAt
                      negotiatedVersion:version
                           sessionState:RNRIPCSmokeSessionStateNone
                                  error:error];
    }];
}

- (void)recordTransportEvent:(RNRMessageTransportDiagnosticEvent)event
           messageIdentifier:(RNRRuntimeMessageIdentifier)messageIdentifier
               attemptNumber:(NSUInteger)attemptNumber
         maximumAttemptCount:(NSUInteger)maximumAttemptCount
                    duration:(NSTimeInterval)duration
                       error:(NSError *)error
        activationSuppressed:(BOOL)activationSuppressed
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (event == RNRMessageTransportDiagnosticEventRequestStarted) {
            self.requestStartedForCurrentOperation = YES;
        }
        [self appendDiagnostic:@"transport id=%@ event=%@ message=%d attempt=%lu/%lu duration_ms=%.1f activation=%@ error_domain=%@ error_code=%ld",
                               self.state.operationIdentifier.UUIDString ?: @"none",
                               RNRIPCSmokeTransportEventName(event),
                               messageIdentifier,
                               (unsigned long)attemptNumber,
                               (unsigned long)maximumAttemptCount,
                               duration * 1000.0,
                               activationSuppressed ? @"suppressed" : @"enabled",
                               error.domain ?: @"none",
                               (long)error.code];
    });
}

- (void)appendDiagnostic:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2)
{
    va_list arguments;
    va_start(arguments, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    NSString *existing = self.diagnosticsView.text ?: @"";
    self.diagnosticsView.text = existing.length > 0
        ? [existing stringByAppendingFormat:@"\n%@", line]
        : line;
    if (self.diagnosticsView.text.length > 0) {
        NSRange end = NSMakeRange(self.diagnosticsView.text.length - 1, 1);
        [self.diagnosticsView scrollRangeToVisible:end];
    }
}

- (void)updateControls
{
    BOOL available = !self.state.isBusy && !self.clientInvalidated;
    BOOL negotiated = self.state.negotiatedVersion >= RNRProtocolVersionMinimumCompatible &&
        self.state.negotiatedVersion <= RNRProtocolVersionCurrent;
    BOOL noSession = self.state.sessionState == RNRIPCSmokeSessionStateNone;

    self.URLField.enabled = available && noSession;
    self.negotiateButton.enabled = available;
    self.incompatibleButton.enabled = available;
    self.openButton.enabled = available && negotiated && noSession;
    self.invalidURLButton.enabled = available && negotiated && noSession;
    self.malformedButton.enabled = available;
    self.closeButton.enabled = available && self.activeSessionIdentifier != nil &&
        self.state.sessionState == RNRIPCSmokeSessionStateActive;
    self.unknownCloseButton.enabled = available;
    self.probeButton.enabled = available;
    self.invalidateButton.enabled = available;
    self.resetRetryButton.enabled = !self.state.isBusy &&
        self.state.sessionState != RNRIPCSmokeSessionStateActive;
}

@end
