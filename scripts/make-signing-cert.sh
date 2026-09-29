#!/usr/bin/env bash
# Creates a stable self-signed code-signing identity "WinTab Dev" in the login
# keychain, so WinTab keeps a constant code identity across rebuilds and macOS
# does NOT re-prompt for Accessibility / Screen Recording after each build.
# Idempotent: does nothing if the identity already exists.
set -euo pipefail

CERT_NAME="WinTab Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "==> Identity '$CERT_NAME' already exists. Nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<'CNF'
[ req ]
distinguished_name = dn
x509_extensions    = v3
prompt             = no
[ dn ]
CN = WinTab Dev
[ v3 ]
keyUsage             = critical, digitalSignature
extendedKeyUsage     = critical, codeSigning
basicConstraints     = critical, CA:false
CNF

echo "==> Generating self-signed code-signing certificate"
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/wintab.key" -out "$TMP/wintab.crt" \
    -days 3650 -config "$TMP/cert.cnf" >/dev/null 2>&1

# -legacy + sha1 MAC + 3DES PBE so Apple's `security` tool can read the p12
# (OpenSSL 3.x defaults are not understood by macOS's SecKeychainItemImport).
# A non-empty transient password is used because empty-password p12 MACs are
# rejected by SecKeychainItemImport.
P12PASS="wintab-transient"
openssl pkcs12 -export -legacy -macalg sha1 \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES \
    -inkey "$TMP/wintab.key" -in "$TMP/wintab.crt" \
    -out "$TMP/wintab.p12" -passout pass:"$P12PASS" >/dev/null 2>&1

echo "==> Importing into login keychain (allowing codesign to use it)"
security import "$TMP/wintab.p12" -k "$KEYCHAIN" -P "$P12PASS" -T /usr/bin/codesign

echo "==> Done. Identity '$CERT_NAME' is ready."
echo "    On the FIRST build after this, macOS may show a one-time dialog"
echo "    'codesign wants to sign using key ... WinTab Dev' — click 'Always Allow'."
