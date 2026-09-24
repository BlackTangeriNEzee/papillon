#!/bin/sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
app="$root/build/MiniDict.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -O -parse-as-library -target arm64-apple-macos14.0 "$root"/mac/*.swift -o "$app/Contents/MacOS/MiniDict"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>MiniDict</string>
  <key>CFBundleIdentifier</key><string>local.mini-dict</string>
  <key>CFBundleName</key><string>MiniDict</string>
  <key>CFBundleDisplayName</key><string>Mini Dict</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSServices</key>
  <array>
    <dict>
      <key>NSMenuItem</key><dict><key>default</key><string>用 Mini Dict 翻译 Translate with Mini Dict</string></dict>
      <key>NSMessage</key><string>translateService</string>
      <key>NSPortName</key><string>MiniDict</string>
      <key>NSSendTypes</key><array><string>public.utf8-plain-text</string></array>
      <key>NSRequiredContext</key><dict/>
    </dict>
  </array>
</dict>
</plist>
PLIST
codesign -s - --force --deep "$app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
echo "$app"
