#!/bin/sh
set -eu
name="Mini Dict Signing"
keychain="$HOME/Library/Keychains/login.keychain-db"
if security find-identity -v -p codesigning | grep -q "\"$name\""; then
  echo "$name already exists"
  exit 0
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -sha256 \
  -subj "/CN=$name" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem"
/usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$name" -passout pass:minidict -out "$tmp/cert.p12"
security import "$tmp/cert.p12" -k "$keychain" -P minidict -T /usr/bin/codesign -T /usr/bin/security
security add-trusted-cert -p codeSign -k "$keychain" "$tmp/cert.pem"
security find-identity -v -p codesigning | grep "\"$name\""
