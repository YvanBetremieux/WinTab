#!/usr/bin/env bash
# Checks that a WinTab.app is releasable: version, Sparkle feed and framework,
# rpath, signature by "WinTab Dev". Usage: check-bundle.sh <app> <version> <build>
set -euo pipefail
APP="$1"; WANT_VERSION="$2"; WANT_BUILD="$3"
PLIST="$APP/Contents/Info.plist"
fail() { echo "check-bundle: $*" >&2; exit 1; }
key() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || true; }

[ "$(key CFBundleShortVersionString)" = "$WANT_VERSION" ] || fail "version $(key CFBundleShortVersionString) ≠ $WANT_VERSION"
[ "$(key CFBundleVersion)" = "$WANT_BUILD" ] || fail "build $(key CFBundleVersion) ≠ $WANT_BUILD"
[ -n "$(key SUFeedURL)" ]     || fail "SUFeedURL missing"
[ -n "$(key SUPublicEDKey)" ] || fail "SUPublicEDKey missing"
[ -d "$APP/Contents/Frameworks/Sparkle.framework" ] || fail "Sparkle.framework missing"
otool -l "$APP/Contents/MacOS/WinTab" | grep '@loader_path/../Frameworks' >/dev/null \
    || fail "rpath @loader_path/../Frameworks missing: Sparkle would not load"
codesign --verify --strict --deep "$APP" || fail "invalid signature"
# A self-signed identity has no Team ID, so hardened-runtime library validation
# rejects Sparkle.framework at launch ("Library not loaded … code signature").
codesign -d --entitlements - --xml "$APP" 2>/dev/null \
    | grep 'com.apple.security.cs.disable-library-validation' >/dev/null \
    || fail "disable-library-validation entitlement missing: dyld would refuse Sparkle.framework"
codesign -dvv "$APP" 2>&1 | grep '^Authority=WinTab Dev$' >/dev/null \
    || fail "not signed by 'WinTab Dev' — users would lose their permissions"
# Actually load the signed binary: catches every dyld/signature refusal at launch.
got_run=$("$APP/Contents/MacOS/WinTab" --version 2>&1) \
    || fail "the app does not launch: $got_run"
[ "$got_run" = "$WANT_VERSION" ] || fail "--version printed '$got_run', want $WANT_VERSION"
echo "check-bundle: OK ($WANT_VERSION / $WANT_BUILD)"
