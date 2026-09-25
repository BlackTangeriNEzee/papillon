#!/bin/sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
app="$root/build/Papillon.app"
if ! security find-identity -v -p codesigning | grep -q '"Mini Dict Signing"'; then
  echo "Signing identity \"Mini Dict Signing\" not found. Run: sh mac/make-cert.sh" >&2
  exit 1
fi
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
sources=$(find "$root/mac" -maxdepth 1 -name '*.swift' ! -name 'make-icon.swift' | sort)
swiftc -O -parse-as-library -target arm64-apple-macos14.0 $sources -o "$app/Contents/MacOS/Papillon"
swift "$root/mac/make-icon.swift" "$root" "$root/build"
cp "$root/build/AppIcon.icns" "$root/build/StatusIcon.png" "$root/build/StatusIcon@2x.png" "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Papillon</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>local.mini-dict</string>
  <key>CFBundleName</key><string>Papillon</string>
  <key>CFBundleDisplayName</key><string>蝶笺</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSServices</key>
  <array>
    <dict>
      <key>NSMenuItem</key><dict><key>default</key><string>用蝶笺翻译 Translate with Papillon</string></dict>
      <key>NSMessage</key><string>translateService</string>
      <key>NSPortName</key><string>Papillon</string>
      <key>NSSendTypes</key><array><string>public.utf8-plain-text</string></array>
      <key>NSRequiredContext</key><dict/>
    </dict>
  </array>
</dict>
</plist>
PLIST
codesign -s "Mini Dict Signing" --force --timestamp=none "$app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
echo "$app"
