#!/bin/zsh
# Builds MicFixer.app and installs it to /Applications.
set -e
cd "${0:A:h}"
APP=build/MicFixer.app
rm -rf build && mkdir -p $APP/Contents/MacOS
swiftc -O -o $APP/Contents/MacOS/MicFixer main.swift
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.micfixer</string>
  <key>CFBundleName</key><string>MicFixer</string>
  <key>CFBundleExecutable</key><string>MicFixer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - $APP
pkill -x MicFixer || true
rm -rf /Applications/MicFixer.app && ditto $APP /Applications/MicFixer.app
open /Applications/MicFixer.app
