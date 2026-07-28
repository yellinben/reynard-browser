#!/bin/sh

set -eu

PACKAGE_IDENTIFIER="com.rpetrich.rocketbootstrap"
MINIMUM_VERSION="1.0.10~beta5"
SOURCE_REFERENCE="Lessica/RocketBootstrap v1.0.10beta5 (8213bbb1202a6bc8fa4ca1fd9f1c8d291057931f)"

fail()
{
	printf 'error: %s\n' "$*" >&2
	exit 1
}

command -v dpkg-query >/dev/null 2>&1 || fail "dpkg-query is required on the candidate device"
command -v dpkg >/dev/null 2>&1 || fail "dpkg is required on the candidate device"

installed_version="$(dpkg-query -W -f='${Version}' "$PACKAGE_IDENTIFIER" 2>/dev/null)" ||
	fail "$PACKAGE_IDENTIFIER is not installed"

if ! dpkg --compare-versions "$installed_version" ge "$MINIMUM_VERSION"; then
	fail "$PACKAGE_IDENTIFIER $installed_version is older than required $MINIMUM_VERSION"
fi

if [ -f /var/jb/usr/lib/librocketbootstrap.dylib ]; then
	library_path="/var/jb/usr/lib/librocketbootstrap.dylib"
elif [ -f /usr/lib/librocketbootstrap.dylib ]; then
	library_path="/usr/lib/librocketbootstrap.dylib"
else
	fail "librocketbootstrap.dylib was not found in the rootless or rootful library location"
fi

printf 'package=%s\n' "$PACKAGE_IDENTIFIER"
printf 'installed_version=%s\n' "$installed_version"
printf 'minimum_version=%s\n' "$MINIMUM_VERSION"
printf 'library_path=%s\n' "$library_path"
printf 'required_source=%s\n' "$SOURCE_REFERENCE"
