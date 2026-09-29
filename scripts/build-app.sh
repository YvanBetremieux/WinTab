#!/usr/bin/env bash
set -euo pipefail

# The macOS 26 Command Line Tools `swift` cannot build SwiftPM packages;
# use the Homebrew Swift toolchain instead.
export PATH="/opt/homebrew/opt/swift/Swift-6.3.xctoolchain/usr/bin:$PATH"

APP="WinTab"
BUNDLE_ID="com.yvanb.wintab"
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
swift build -c release

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
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
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
