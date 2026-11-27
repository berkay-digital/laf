#!/bin/zsh
# Builds Laf.app and installs it to ~/Applications.
#
# Environment:
#   SIGN_IDENTITY  Codesigning identity. Default: a self-signed "Laf Local Signing" certificate,
#                  created in your login keychain on first run. Use "-" for ad-hoc signing, or a
#                  "Developer ID Application: ..." identity for builds you distribute.
#   BUNDLE_ID      Default: io.github.berkay-digital.laf
#   VERSION        Default: 0.1.0
#   INSTALL        Set to 0 to only build into macos/build/.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Laf.app
BUNDLE_ID=${BUNDLE_ID:-io.github.berkay-digital.laf}
VERSION=${VERSION:-0.1.0}
VERSION=${VERSION#v} # accept git tags like v0.1.0
LOCAL_IDENTITY="Laf Local Signing"
IDENTITY=${SIGN_IDENTITY:-$LOCAL_IDENTITY}

rm -rf build
mkdir -p "$APP/Contents/MacOS"

swiftc -O -swift-version 5 -target arm64-apple-macos14.0 \
  -framework Cocoa -framework AVFoundation -framework ApplicationServices -framework ServiceManagement \
  App/main.swift -o "$APP/Contents/MacOS/Laf"

# On-device Parakeet speech server (FluidAudio / Core ML). The model downloads on first launch.
swift build -c release --disable-keychain --package-path parakeet-server --product parakeet-server
cp parakeet-server/.build/release/parakeet-server "$APP/Contents/MacOS/"

# App icon, from the 1024 px master.
mkdir -p "$APP/Contents/Resources" build/AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s AppIcon.png --out build/AppIcon.iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s * 2)) $((s * 2)) AppIcon.png --out build/AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>Laf</string>
  <key>CFBundleExecutable</key><string>Laf</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Laf records your voice while you hold the dictation key.</string>
</dict>
</plist>
PLIST

# A stable self-signed identity keeps macOS privacy permissions across rebuilds
# (ad-hoc signatures change every build, so macOS asks for Accessibility and Microphone again).
if [[ "$IDENTITY" == "$LOCAL_IDENTITY" ]] && ! security find-certificate -c "$LOCAL_IDENTITY" >/dev/null 2>&1; then
  echo "Creating the \"$LOCAL_IDENTITY\" certificate in your login keychain"
  tmp=$(mktemp -d)
  pass=$(openssl rand -hex 16)
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$LOCAL_IDENTITY" \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" \
    -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
  openssl pkcs12 -export -legacy -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/id.p12" -passout "pass:$pass" 2>/dev/null \
    || openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/id.p12" -passout "pass:$pass"
  security import "$tmp/id.p12" -k ~/Library/Keychains/login.keychain-db -P "$pass" -T /usr/bin/codesign
  rm -rf "$tmp"
fi

sign() { # sign <path> <identifier>
  if [[ "$IDENTITY" == Developer\ ID* ]]; then
    codesign --force --options runtime --timestamp --entitlements Laf.entitlements \
      --sign "$IDENTITY" --identifier "$2" "$1"
  elif ! codesign --force --sign "$IDENTITY" --identifier "$2" "$1" 2>/dev/null; then
    echo "warning: signing with \"$IDENTITY\" failed, using ad-hoc"
    codesign --force --sign - --identifier "$2" "$1"
  fi
}
sign "$APP/Contents/MacOS/parakeet-server" "$BUNDLE_ID.parakeet"
sign "$APP" "$BUNDLE_ID"
echo "Built $PWD/$APP"

[[ "${INSTALL:-1}" == 0 ]] && exit 0
mkdir -p ~/Applications
pkill -x Laf 2>/dev/null && sleep 0.5 || true
rm -rf ~/Applications/Laf.app
cp -R "$APP" ~/Applications/
echo "Installed ~/Applications/Laf.app"
