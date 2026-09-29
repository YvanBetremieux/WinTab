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
# Overridden by the release workflow with the tag (v1.2.3 -> 1.2.3).
VERSION="${VERSION:-1.0}"
RELEASE_BIN=".build/release/$APP"
APP_DIR="$APP.app"
INSTALL_DIR="/Applications"

# Stable signing identity so macOS keeps Accessibility / Screen-Recording
# permissions across rebuilds. Falls back to ad-hoc if the cert is missing.
SIGN_IDENTITY="WinTab Dev"
if ! security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
    echo "!! Signing identity '$SIGN_IDENTITY' not found."
    echo "!! Run ./scripts/make-signing-cert.sh once to keep permissions across builds."
    echo "!! Falling back to ad-hoc signing (permissions WILL reset each build)."
    SIGN_IDENTITY="-"
fi

echo "==> swift build -c release"
"$SWIFT" build -c release

echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$RELEASE_BIN" "$APP_DIR/Contents/MacOS/$APP"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP</string>
    <key>CFBundleExecutable</key><string>$APP</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>WinTab affiche un aperçu de vos fenêtres ouvertes.</string>
</dict>
</plist>
PLIST

echo "==> Signing with identity: $SIGN_IDENTITY"
codesign --force --deep --sign "$SIGN_IDENTITY" --options runtime "$APP_DIR"

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
