#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/../.." && pwd)"
PROJECT_PATH="$ROOT_DIR/browser/Reynard.xcodeproj"
SCHEME="ReynardServices"

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/reynard-client-boundary.XXXXXX")"
DERIVED_DATA="$TEMP_DIR/DerivedData"
SUBMODULES_BEFORE="$TEMP_DIR/submodules-before.txt"
SUBMODULES_AFTER="$TEMP_DIR/submodules-after.txt"
SUBMODULE_SNAPSHOT_READY=0

fail()
{
	printf 'error: %s\n' "$*" >&2
	return 1
}

snapshot_submodules()
{
	git -C "$ROOT_DIR" submodule status --recursive
}

cleanup()
{
	result=$?
	trap - EXIT

	if [ "$SUBMODULE_SNAPSHOT_READY" -eq 1 ]; then
		if snapshot_submodules > "$SUBMODULES_AFTER"; then
			if ! cmp -s "$SUBMODULES_BEFORE" "$SUBMODULES_AFTER"; then
				printf 'error: submodule state changed during client-boundary verification:\n' >&2
				diff -u "$SUBMODULES_BEFORE" "$SUBMODULES_AFTER" >&2 || true
				result=1
			fi
		else
			printf 'error: could not capture submodule state after verification\n' >&2
			result=1
		fi
	fi

	rm -rf "$TEMP_DIR"
	exit "$result"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [ ! -d "$PROJECT_PATH" ]; then
	fail "missing Xcode project at $PROJECT_PATH"
fi

for source_dir in \
	"$ROOT_DIR/browser/ReynardProtocol" \
	"$ROOT_DIR/browser/ReynardServices"
do
	if [ ! -d "$source_dir" ]; then
		fail "missing client-boundary source directory at $source_dir"
	fi
done

if ! snapshot_submodules > "$SUBMODULES_BEFORE"; then
	fail "could not capture submodule state before verification"
fi
SUBMODULE_SNAPSHOT_READY=1

printf '%s\n' 'Checking client-boundary imports...'
IMPORT_REPORT="$TEMP_DIR/forbidden-imports.txt"
IMPORT_PATTERN='^[[:space:]]*#[[:space:]]*(import|include)[[:space:]]*[<"][^>"]*(gecko|xul|mozilla|idevice)|^[[:space:]]*(@import|import)[[:space:]]+[^;[:space:]]*(gecko|xul|mozilla|idevice)'
import_status=0
rg --line-number --ignore-case \
	--glob '*.h' \
	--glob '*.m' \
	--glob '*.mm' \
	--glob '*.swift' \
	"$IMPORT_PATTERN" \
	"$ROOT_DIR/browser/ReynardProtocol" \
	"$ROOT_DIR/browser/ReynardServices" > "$IMPORT_REPORT" || import_status=$?

case "$import_status" in
	0)
		printf '%s\n' 'error: forbidden Gecko/XUL/Mozilla/idevice imports found:' >&2
		cat "$IMPORT_REPORT" >&2
		exit 1
		;;
	1)
		;;
	*)
		fail "source import scan failed with status $import_status"
		;;
esac

printf '%s\n' 'Resolving client-boundary build settings...'
BUILD_SETTINGS="$TEMP_DIR/build-settings.txt"
if ! xcodebuild \
	-project "$PROJECT_PATH" \
	-scheme "$SCHEME" \
	-configuration Debug \
	-sdk iphonesimulator \
	-destination 'generic/platform=iOS Simulator' \
	-derivedDataPath "$DERIVED_DATA" \
	SYMROOT="$DERIVED_DATA/Build/Products" \
	OBJROOT="$DERIVED_DATA/Build/Intermediates.noindex" \
	CODE_SIGNING_ALLOWED=NO \
	CODE_SIGNING_REQUIRED=NO \
	-showBuildSettings > "$BUILD_SETTINGS" 2>&1
then
	tail -n 100 "$BUILD_SETTINGS" >&2
	fail "could not resolve build settings for the $SCHEME scheme"
fi

SETTINGS_AUDIT="$TEMP_DIR/settings-audit.txt"
awk '
	/^[[:space:]]*(HEADER_SEARCH_PATHS|LIBRARY_SEARCH_PATHS|FRAMEWORK_SEARCH_PATHS|OTHER_LDFLAGS|SWIFT_OBJC_BRIDGING_HEADER)[[:space:]]*=/ {
		print
	}
' "$BUILD_SETTINGS" > "$SETTINGS_AUDIT"

if [ ! -s "$SETTINGS_AUDIT" ]; then
	fail "no dependency-boundary settings were present in xcodebuild output"
fi

LEAKED_SETTINGS="$TEMP_DIR/leaked-settings.txt"
if grep -Ein '(gecko|xul|mozilla|idevice)' "$SETTINGS_AUDIT" > "$LEAKED_SETTINGS"; then
	printf '%s\n' 'error: forbidden dependency leaked into resolved build settings:' >&2
	cat "$LEAKED_SETTINGS" >&2
	exit 1
fi

BRIDGING_HEADERS="$TEMP_DIR/bridging-headers.txt"
awk '
	/^[[:space:]]*SWIFT_OBJC_BRIDGING_HEADER[[:space:]]*=/ {
		value = $0
		sub(/^[[:space:]]*SWIFT_OBJC_BRIDGING_HEADER[[:space:]]*=[[:space:]]*/, "", value)
		if (value ~ /[^[:space:]]/) {
			print
		}
	}
' "$SETTINGS_AUDIT" > "$BRIDGING_HEADERS"

if [ -s "$BRIDGING_HEADERS" ]; then
	printf '%s\n' 'error: client-boundary targets must not use bridging headers:' >&2
	cat "$BRIDGING_HEADERS" >&2
	exit 1
fi

printf '%s\n' 'Building the client boundary for testing...'
BUILD_LOG="$TEMP_DIR/build.log"
if ! xcodebuild \
	-project "$PROJECT_PATH" \
	-scheme "$SCHEME" \
	-configuration Debug \
	-sdk iphonesimulator \
	-destination 'generic/platform=iOS Simulator' \
	-derivedDataPath "$DERIVED_DATA" \
	SYMROOT="$DERIVED_DATA/Build/Products" \
	OBJROOT="$DERIVED_DATA/Build/Intermediates.noindex" \
	CODE_SIGNING_ALLOWED=NO \
	CODE_SIGNING_REQUIRED=NO \
	build-for-testing > "$BUILD_LOG" 2>&1
then
	tail -n 100 "$BUILD_LOG" >&2
	fail "build-for-testing failed for the $SCHEME scheme"
fi

FRAMEWORK_DIR=''
for candidate in "$DERIVED_DATA"/Build/Products/*/ReynardServices.framework
do
	if [ ! -d "$candidate" ]; then
		continue
	fi
	if [ -n "$FRAMEWORK_DIR" ]; then
		fail "found more than one built ReynardServices.framework under $DERIVED_DATA/Build/Products"
	fi
	FRAMEWORK_DIR="$candidate"
done

if [ -z "$FRAMEWORK_DIR" ]; then
	fail "could not find built ReynardServices.framework under $DERIVED_DATA/Build/Products"
fi

FRAMEWORK_BINARY="$FRAMEWORK_DIR/ReynardServices"
if [ ! -f "$FRAMEWORK_BINARY" ]; then
	fail "missing framework executable at $FRAMEWORK_BINARY"
fi

printf '%s\n' 'Auditing the built framework...'
OTOOL_REPORT="$TEMP_DIR/otool.txt"
if ! xcrun otool -L "$FRAMEWORK_BINARY" > "$OTOOL_REPORT" 2>&1; then
	cat "$OTOOL_REPORT" >&2
	fail "otool could not inspect $FRAMEWORK_BINARY"
fi

LINKED_FORBIDDEN="$TEMP_DIR/linked-forbidden.txt"
if grep -Ein '(gecko|xul|mozilla|idevice|nss3|freebl3|softokn3|lgpllibs|gkcodecs)' "$OTOOL_REPORT" > "$LINKED_FORBIDDEN"; then
	printf '%s\n' 'error: ReynardServices links a forbidden runtime dependency:' >&2
	cat "$LINKED_FORBIDDEN" >&2
	exit 1
fi

NM_REPORT="$TEMP_DIR/nm.txt"
if ! xcrun nm -u "$FRAMEWORK_BINARY" > "$NM_REPORT" 2>&1; then
	cat "$NM_REPORT" >&2
	fail "nm could not inspect $FRAMEWORK_BINARY"
fi

SYMBOL_PATTERN='(gecko|xul|mozilla|idevice|XRE_|NS_InitXPCOM|(^|[^[:alnum:]_])_?moz_|_?JS_(Init|NewContext|NewGlobalObject|Shutdown))'
FORBIDDEN_SYMBOLS="$TEMP_DIR/forbidden-symbols.txt"
if grep -Ein "$SYMBOL_PATTERN" "$NM_REPORT" > "$FORBIDDEN_SYMBOLS"; then
	printf '%s\n' 'error: ReynardServices references forbidden Gecko entry points:' >&2
	cat "$FORBIDDEN_SYMBOLS" >&2
	exit 1
fi

printf '%s\n' 'Client-boundary verification passed.'
