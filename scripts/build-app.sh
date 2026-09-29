#!/usr/bin/env bash
set -euo pipefail

# Toolchain selection.
#
# History: on macOS 26.0 the Command Line Tools `swift` could not build any
# SwiftPM package (a dropped PackageDescription symbol), so this script forced
# the Homebrew toolchain. That is no longer true: the CLT/Xcode `swift` (6.4+)
# builds this package fine, and it is now the *Homebrew* toolchain (6.3.x) that
# fails against the current macOS SDK. So: use whatever `swift` is on PATH, and
# let it be overridden explicitly when needed.
#
#   SWIFT=/opt/homebrew/opt/swift/Swift-6.3.xctoolchain/usr/bin/swift ./scripts/build-app.sh
SWIFT="${SWIFT:-swift}"

if ! command -v "$SWIFT" >/dev/null 2>&1; then
    echo "!! No Swift toolchain found (looked for: $SWIFT)."
    echo "!! Install Xcode or the Command Line Tools: xcode-select --install"
    exit 1
fi
echo "==> Toolchain: $("$SWIFT" --version 2>/dev/null | head -1)"

APP="WinTab"
BUNDLE_ID="com.yvanb.wintab"
APP_DIR="$APP.app"
INSTALL_DIR="/Applications"

# Version: major.minor from VERSION; the release workflow sets the full version
# (1.0.<run>) and the build number (<run>), which Sparkle requires to increase.
WINTAB_VERSION="${WINTAB_VERSION:-$(tr -d '[:space:]' < VERSION).0}"
WINTAB_BUILD="${WINTAB_BUILD:-0}"

# Stable signing identity so macOS keeps Accessibility / Screen-Recording
# permissions across rebuilds *and* across Sparkle updates. Locally it falls back
# to ad-hoc; the release workflow sets WINTAB_REQUIRE_IDENTITY=1 so a missing
# certificate fails the release instead of shipping an ad-hoc build.
SIGN_IDENTITY="${WINTAB_SIGN_IDENTITY:-WinTab Dev}"
if ! security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
    if [ "${WINTAB_REQUIRE_IDENTITY:-0}" = "1" ]; then
        echo "!! Signing identity '$SIGN_IDENTITY' not found and WINTAB_REQUIRE_IDENTITY=1."
        exit 1
    fi
    echo "!! Signing identity '$SIGN_IDENTITY' not found."
    echo "!! Run ./scripts/make-signing-cert.sh once to keep permissions across builds."
    echo "!! Falling back to ad-hoc signing (permissions WILL reset each build)."
    SIGN_IDENTITY="-"
fi

# Sparkle is only switched on when a feed is given (the release workflow).
# Local builds have no feed, so a release never overwrites a development build.
SPARKLE_KEYS=""
if [ -n "${WINTAB_FEED_URL:-}" ]; then
    SPARKLE_KEYS="    <key>SUFeedURL</key><string>$WINTAB_FEED_URL</string>
    <key>SUPublicEDKey</key><string>$(tr -d '[:space:]' < scripts/sparkle-public-key.txt)</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUAutomaticallyUpdate</key><true/>"
fi

echo "==> swift build -c release"
"$SWIFT" build -c release
BIN_DIR="$("$SWIFT" build -c release --show-bin-path)"

echo "==> Assembling $APP_DIR ($WINTAB_VERSION / $WINTAB_BUILD)"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Frameworks" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/$APP" "$APP_DIR/Contents/MacOS/$APP"

# Sparkle.framework: SwiftPM copies it next to the binary; fall back to the
# macOS slice of the xcframework.
SPARKLE_FW="$BIN_DIR/Sparkle.framework"
if [ ! -d "$SPARKLE_FW" ]; then
    SPARKLE_FW="$(find .build/artifacts -path '*macos*' -name Sparkle.framework -type d | head -1)"
fi
if [ ! -d "$SPARKLE_FW" ]; then
    echo "!! Sparkle.framework not found in .build — the app would crash at launch."
    exit 1
fi
cp -R "$SPARKLE_FW" "$APP_DIR/Contents/Frameworks/"

# dyld looks for @rpath/Sparkle.framework; point it at Contents/Frameworks.
if ! otool -l "$APP_DIR/Contents/MacOS/$APP" | grep '@loader_path/../Frameworks' >/dev/null; then
    install_name_tool -add_rpath '@loader_path/../Frameworks' "$APP_DIR/Contents/MacOS/$APP"
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP</string>
    <key>CFBundleExecutable</key><string>$APP</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$WINTAB_VERSION</string>
    <key>CFBundleVersion</key><string>$WINTAB_BUILD</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>WinTab affiche un aperçu de vos fenêtres ouvertes.</string>
$SPARKLE_KEYS
</dict>
</plist>
PLIST

# Inside-out signing, in the order Sparkle documents: nested helpers, then the
# framework, then the app. --deep is not used (deprecated for signing).
echo "==> Signing with identity: $SIGN_IDENTITY"
sign() { codesign --force --sign "$SIGN_IDENTITY" --options runtime "$@"; }
FW="$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B"
for nested in "$FW/XPCServices/Installer.xpc" "$FW/Autoupdate" "$FW/Updater.app"; do
    if [ -e "$nested" ]; then sign "$nested"; fi
done
if [ -e "$FW/XPCServices/Downloader.xpc" ]; then
    sign --preserve-metadata=entitlements "$FW/XPCServices/Downloader.xpc"
fi
sign "$APP_DIR/Contents/Frameworks/Sparkle.framework"
sign --entitlements scripts/WinTab.entitlements "$APP_DIR"
codesign --verify --strict --deep "$APP_DIR"

if [ "${1:-}" = "--install" ]; then
    echo "==> Installing to $INSTALL_DIR and relaunching"
    # Quit the running instance (ignore errors if not running).
    osascript -e 'quit app "WinTab"' >/dev/null 2>&1 || true
    pkill -x "$APP" >/dev/null 2>&1 || true
    sleep 1
    rm -rf "$INSTALL_DIR/$APP_DIR"
    cp -R "$APP_DIR" "$INSTALL_DIR/"
    open "$INSTALL_DIR/$APP_DIR"
    echo "==> Installed and launched from $INSTALL_DIR/$APP_DIR"
else
    echo "==> Built $APP_DIR. Run with --install to copy to $INSTALL_DIR and relaunch."
fi
