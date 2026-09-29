#!/usr/bin/env bash
# Tests make-appcast.sh with a throwaway ed25519 key (never the keychain one).
set -euo pipefail
cd "$(dirname "$0")/.."
BIN=.build/artifacts/sparkle/Sparkle/bin
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# A Sparkle ed25519 private key is 32 arbitrary bytes, base64-encoded.
KEY=$(openssl rand -base64 32)
mkdir "$T/dir with space"; echo hello > "$T/dir with space/f"
ZIP="$T/dir with space/WinTab-1.0.7.zip"
ditto -c -k --keepParent "$T/dir with space/f" "$ZIP"

SPARKLE_ED_PRIVATE_KEY="$KEY" scripts/make-appcast.sh "$ZIP" \
    1.0.7 7 "https://example.com/dl?a=1&b=2" "https://example.com/notes" "$T/appcast.xml"
xmllint --noout "$T/appcast.xml"
grep -q 'sparkle:version="7"' "$T/appcast.xml"
grep -q 'sparkle:shortVersionString="1.0.7"' "$T/appcast.xml"
grep -q '<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>' "$T/appcast.xml"
grep -q 'dl?a=1&amp;b=2' "$T/appcast.xml"
SIG=$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' "$T/appcast.xml")
echo "$KEY" | "$BIN/sign_update" --ed-key-file - --verify "$ZIP" "$SIG"

# Invalid key → failure, and no file written.
if SPARKLE_ED_PRIVATE_KEY="nope" scripts/make-appcast.sh "$ZIP" \
    1.0.7 7 u n "$T/bad.xml" 2>/dev/null; then echo "FAIL: invalid key accepted"; exit 1; fi
[ ! -e "$T/bad.xml" ] || { echo "FAIL: partial appcast written"; exit 1; }
echo "test-make-appcast: OK"
