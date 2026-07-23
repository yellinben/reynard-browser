# Reynard runtime architecture

## Status and scope

This document is the authoritative architecture reference for evolving this
Reynard fork into the runtime used by InAppReynard. It consolidates the
pre-fork feasibility research and adapts it to the repository as it existed at
commit `aaa08cc` on 2026-07-22.

The immediate objective is not a general replacement for WebKit. The first
compatibility target is selected uses of `SFSafariViewController` in explicitly
enabled applications on jailbroken iOS 15. InAppReynard performs the runtime
interception in a separate repository. This repository owns Reynard, Gecko,
the client facade, the IPC contract, the host process, and runtime packaging.

Do not reorganize the existing source tree merely to match a conceptual final
layout. Add boundaries incrementally and keep upstream synchronization
reviewable.

## Non-negotiable boundaries

1. `ReynardServices.framework` must never link `GeckoView.framework`, XUL, or
   any Gecko library.
2. Only the host side may initialize Gecko or receive Gecko/JIT/helper
   privileges.
3. `ReynardProtocol` must remain a small wire contract, not a shared-utilities
   target.
4. InAppReynard remains a separate Theos repository. Neither repository is a
   submodule of the other.
5. InAppReynard dynamically locates `ReynardServices` and fails open to native
   SafariServices when the runtime is missing, incompatible, or unsupported.
6. Stage 1 uses the existing `Reynard.app` as the Gecko host. A separate
   `ReynardHost.app` is extracted only after IPC and remote presentation work.
7. The existing `engine/firefox` and `support/idevice` submodules remain owned
   by this Reynard superproject. Routine client-side work must not initialize or
   build Firefox.

## Current checkout baseline

The current Xcode project is `browser/Reynard.xcodeproj` and has four shared
targets and schemes:

| Target | Current product | Current responsibility |
| --- | --- | --- |
| `Reynard` | `Reynard.app` | Browser UI, JIT setup, Gecko process startup, and runtime packaging owner |
| `GeckoView` | `GeckoView.framework` | Gecko runtime/session/view bridge and Gecko-facing delegates |
| `Reynard Helper` | `Reynard Helper.appex` | Multi-instance Gecko child-process extension |
| `OpenIn` | `OpenIn.appex` | System entry point for opening content in Reynard |

The source tree already separates the most important responsibilities:

```text
browser/
├── Configuration/
├── Extensions/OpenIn/
├── GeckoView/
├── Helper/
├── Reynard/
├── Reynard.xcodeproj/
└── Scripts/
```

This separation should be extended in place with `browser/ReynardProtocol`
and `browser/ReynardServices`. A future `browser/ReynardHost` directory should
be created only during host extraction.

### Current engine ownership

`browser/Reynard/main.swift` performs user-data migration, starts the JIT
controller, configures the unsandboxed data path on older systems when needed,
and calls `GeckoRuntime.main`. That bridge calls Gecko's main-process entry
point. The app therefore owns process startup rather than embedding Gecko into
an already-running arbitrary UIKit application.

The `Reynard` target currently:

- Depends on `GeckoView`, `Reynard Helper`, and `OpenIn`.
- Links XUL and the Gecko support libraries through `OTHER_LDFLAGS`.
- Embeds `GeckoView.framework` and both app extensions.
- Runs `browser/Scripts/AddGecko.sh` to stage XUL, dylibs, resources, and the
  default theme into the application bundle.

These are host-side responsibilities. They must not migrate into
`ReynardServices`.

### Current helper model

`Reynard Helper.appex` is embedded in `Reynard.app`. Its property list declares
a private, multi-instance application-style XPC service. This matches the
present assumption that the application owning Gecko also owns its child
process helper.

An injected framework cannot add that helper to a third-party application's
signed bundle. This is one of the main reasons the runtime must remain in a
dedicated Reynard-owned process.

### Current submodule and build model

The repository declares, but a normal clone does not need to initialize:

```text
engine/firefox   https://github.com/mozilla-firefox/firefox
support/idevice  https://github.com/jkcoxson/idevice
```

`tools/development/update-gecko.sh` shallow-initializes Firefox at the release
tag in `engine/release.txt`. The patch scripts maintain Reynard's Gecko changes
under `patches/`. `tools/development/build-idevice.sh` initializes only the
idevice submodule when that library is needed.

Client facade and protocol builds must not depend on either submodule. Gecko is
a separately prepared artifact consumed by the host-side build.

## Intended products

| Product | Type | Loaded by | Responsibility |
| --- | --- | --- | --- |
| `ReynardProtocol` | Objective-C static library | Client facade and host | Versioned IPC messages, identifiers, interfaces, and errors |
| `ReynardServices.framework` | Dynamic framework | Injected clients and, eventually, `Reynard.app` | UIKit facade, host connection, session proxy, and remote presentation |
| `GeckoView.framework` | Existing dynamic framework | Host only | Gecko runtime, sessions, views, delegates, and engine bridge |
| Stage 1 host | Existing `Reynard.app` | System | Existing browser plus initial IPC service and Gecko ownership |
| `ReynardHost.app` | Future hidden application | System | Final Gecko owner, session broker, profiles, helpers, and privileges |
| `Reynard Helper.appex` | Existing app extension | Gecko host | Gecko child/content processes |
| `Reynard.app` | Existing application | User | Browser UI; eventually a client of `ReynardServices` |
| `OpenIn.appex` | Existing app extension | System extension host | Sends URLs to the browser UI |

The final dependency direction is:

```text
InAppReynard clients ─┐
                      ├─> ReynardServices.framework ─> ReynardProtocol
Reynard.app ──────────┘               │
                                      │ IPC / remote presentation
                                      v
                               ReynardHost.app ─> ReynardProtocol
                                      │
                                      ├─> GeckoView.framework ─> Gecko/XUL
                                      └─> Reynard Helper.appex
```

There is no dependency from `ReynardProtocol` back into either side and no
dependency from `ReynardServices` into the host implementation.

## `ReynardProtocol`

`ReynardProtocol` is a statically linked Objective-C contract shared by the
client and host. It should depend on Foundation and, only when unavoidable,
CoreGraphics. It must not import UIKit, Gecko types, browser UI, profile code,
preferences, JIT code, or general-purpose helpers.

The first contract should contain only:

- A monotonically increasing protocol version and compatible range.
- Opaque session and client identifiers.
- Client and host interfaces for opening and closing a session.
- A minimal session request containing a URL and deliberately small options.
- Connection/session lifecycle events.
- Stable error domain and codes.

Navigation state, input, surface descriptors, scripting, downloads, and other
features belong in later contract revisions when a prototype requires them.
Property-list-safe values or narrowly defined `NSSecureCoding` objects are
preferred to Swift types at the process boundary.

The transport mechanism is not part of the domain model. The protocol types
must be usable by a real XPC/Mach transport and by an in-process mock. This
keeps client UI tests independent from Gecko and from a running host.

## `ReynardServices.framework`

This is the only Reynard runtime product loaded into arbitrary client
applications. Its public ABI should be Objective-C for iOS 15 and Theos
compatibility even if implementation code later uses Swift or Objective-C++.

It owns:

- `ReynardViewController` and its configuration/delegate facade.
- Host discovery, protocol negotiation, and connection lifecycle.
- Session creation and cleanup.
- Remote-view or surface integration.
- Client-side presentation, browser chrome, input coordination, sharing, and
  accessibility bridging.
- A mockable host-connection boundary used by tests and development previews.

It does not own:

- Gecko initialization or shutdown.
- Gecko sessions, profiles, XUL, or engine resources.
- JIT enablement or privileged entitlements.
- Gecko helper discovery or process creation.
- Runtime package installation.

The framework should reject an incompatible host before creating a session and
surface a precise failure to InAppReynard so the tweak can use native
SafariServices instead.

## Host responsibilities

The host owns every responsibility that requires Gecko, its resource bundle,
its helper, or elevated privileges:

- Process-wide Gecko initialization and lifecycle.
- Session and client registries.
- Gecko profiles and isolation policy.
- Gecko helper discovery and child-process lifecycle.
- Remote browser views or exported compositing surfaces.
- Client authentication, message validation, and client-death cleanup.
- Memory pressure, background execution, restart, and crash recovery.
- JIT and other narrowly audited private entitlements.

Web content must remain isolated from broad host privileges. A Gecko renderer
compromise must not automatically gain root, platform-application, or
unsandboxed host capabilities.

## Migration stages

### Stage 1: existing `Reynard.app` acts as host

Add `ReynardProtocol` and `ReynardServices`, then expose a minimal service from
the existing application while retaining its current direct Gecko startup:

```text
Injected application
  -> ReynardServices.framework
     -> existing Reynard.app
        -> GeckoView.framework
        -> Reynard Helper.appex
```

This stage proves version negotiation, session lifetime, remote presentation,
touch/input behavior, and failure recovery without simultaneously rewriting
Gecko startup or the standalone browser UI.

Keeping a normally user-facing application available as a background service
has lifecycle limitations. Those limitations are acceptable for a prototype
and should be measured rather than hidden behind premature abstractions.

### Stage 2: extract `ReynardHost.app`

After the Stage 1 service works, move Gecko startup, profiles, helper ownership,
and privileged entitlements into a hidden host application. Then migrate the
normal browser UI to use the same `ReynardServices` path as injected clients.

Do not combine this extraction with the first protocol/framework checkpoint.

## InAppReynard boundary

InAppReynard is responsible for:

- Per-process and per-application enablement.
- Intercepting selected SafariServices construction paths.
- Translating Apple configuration objects into Reynard configuration.
- Translating Reynard events back to the Safari delegate selectors expected by
  already-compiled applications.
- Dynamically loading the deployed client framework.
- Checking protocol/runtime compatibility.
- Failing open to the untouched native controller.

The runtime repository may publish versioned public headers or a small SDK
artifact for InAppReynard to vendor at build time. It must not require the tweak
repository to clone Reynard or Gecko, and the runtime must not include the tweak
as a submodule.

## SafariServices compatibility scope

`SFSafariViewController` is the first compatibility target because its public
surface is much narrower than `WKWebView`. The initial goal is ordinary HTTPS
browsing in an explicit application/domain allowlist, with native fallback for
unsupported or sensitive behavior.

Construction-time substitution is the preferred tweak-side experiment because
the application's own controller reference then points at the object that is
presented. Presentation-time substitution remains a fallback. Runtime class
identity, delegate ordering, styling, interactive dismissal, and native
fallback require device characterization before compatibility claims expand.

Do not include `ASWebAuthenticationSession`, payments, passkeys, Apple ID,
Private Click Measurement, or a general `WKWebView` facade in the initial
scope. Authentication and other sensitive flows remain native unless they are
individually understood and tested.

## Remote presentation constraints

A raw `IOSurface` or hosted Core Animation layer carries pixels, not UIKit
semantics. A useful remote browser must address:

- Touch targeting, gesture arbitration, scrolling, and edge gestures.
- Keyboard focus, marked text, selection, and edit menus.
- Rotation, safe areas, sheets, and application/scene transitions.
- Accessibility elements, focus, and announcements.
- Context menus, link previews, drag and drop, file input, and sharing.

A private UIKit remote-view-controller mechanism may preserve more of these
behaviors than manual surface and input forwarding. The Stage 1 experiment
should compare mechanisms before the wire contract permanently encodes one.

## Build and scheme direction

The eventual focused shared schemes should be:

- `ReynardServices`: `ReynardProtocol`, `ReynardServices`, and their fast tests;
  must build without Gecko or either submodule.
- `ReynardHost`: `ReynardProtocol`, `GeckoView`, `Reynard Helper`, and the host.
- `Reynard`: the standalone browser and its required runtime components.
- `ReynardRuntime`: aggregate packaging and compatibility verification.

The existing four schemes remain unchanged during setup. New schemes should be
introduced with their actual targets, not as empty aggregate scaffolding.

Host-side builds should consume a staged Gecko output and record a manifest
containing at least the Firefox commit/tag, Reynard patch-set revision,
architecture, build configuration, and runtime/protocol versions. Routine
Xcode builds must not compile Firefox from scratch.

## Packaging and versioning

The runtime repository owns one release version for its coordinated products
and a separate monotonic IPC protocol version. Package version equality alone
does not establish wire compatibility.

The eventual rootless runtime package contains the browser/host application,
`ReynardServices.framework`, `GeckoView.framework`, the helper, Gecko/XUL
resources, and required registration configuration. InAppReynard is packaged
separately and declares a minimum runtime dependency while retaining dynamic
loading and native fail-open behavior.

Rootless paths must be resolved through a central deployment/path facility.
Do not scatter a literal `/var/jb` prefix across sources. Packaging and
entitlements require a dedicated later audit; the current private entitlement
files are evidence of the existing runtime's needs, not a template to copy
wholesale into new products.

## Security and fallback policy

The replacement is opt-in per application and should use native behavior when:

- The host or framework is absent, incompatible, or fails during startup.
- The URL, domain, or application is not explicitly enabled.
- The requested API has no faithful implementation.
- Authentication, payment, passkey, Apple ID, or similarly sensitive behavior
  is expected.
- Native-only attribution, extension, or system integration is requested.

The client facade must identify the experience as Reynard rather than
impersonating trusted Safari chrome. Gecko cannot transparently share Safari's
cookies, AutoFill, tracking state, or security UI. The host needs an explicit
profile policy; per-client persistent profiles are a defensible initial default,
with ephemeral sessions added deliberately.

All IPC inputs are untrusted. The host must authenticate clients as far as the
platform permits, validate messages, bind sessions to their owners, and remove
sessions when clients die. Timeouts should produce an observable failure and
native fallback rather than an indefinitely blank controller.

## Implemented client-boundary slice

The first implementation checkpoint establishes a contract boundary without
touching Gecko startup or remote rendering:

1. An Objective-C `ReynardProtocol` static-library target lives under
   `browser/ReynardProtocol`.
2. It defines protocol version constants, an opaque session identifier, a minimal
   open-session request, stable errors, and client/host lifecycle interfaces.
3. A Foundation-only `ReynardServices` framework target lives under
   `browser/ReynardServices` with an internal host-connecting interface that can
   be supplied by a mock.
4. The explicit `ReynardServices` scheme builds and tests with the Firefox and
   idevice submodules uninitialized.
5. `tools/ci/verify-client-boundary.sh` fails if the framework imports or links
   Gecko/XUL and confirms that verification does not change submodule state.

The hostless boundary tests pass on iOS 15.2 and iOS 18.1 Simulators. This slice
does not add `ReynardHost.app`, remote surfaces, Safari hooks,
profile management, packaging, or broad UI facades. Its value is making the
critical dependency invariant executable before more code depends on it.

## Deferred decisions

The following decisions require prototypes or device evidence and are not
settled by this document:

- XPC/Mach transport and host activation mechanism on the supported jailbreak.
- Private remote-view-controller versus manual surface transport.
- Exact protocol serialization and compatibility policy beyond the first
  version constants.
- Host background-lifetime and relaunch behavior during Stage 1.
- Per-application profile identifiers and data-retention controls.
- Minimum entitlement set for the final host and helper.
- How the standalone browser transitions to `ReynardServices` after host
  extraction.

These unknowns should remain explicit. They are reasons for narrow experiments,
not reasons to couple the client framework to Gecko.
