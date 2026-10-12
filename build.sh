#!/bin/zsh
# Compila "Wii.app" y la instala en /Applications
set -e
cd "$(dirname "$0")"
APP=build/Wii.app
rm -rf build && mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
# Binario universal: funciona en Macs con chip Apple y con Intel
for arch in arm64 x86_64; do
  swiftc -O -target $arch-apple-macos14.0 -parse-as-library main.swift -o build/Wii-$arch
done
lipo -create build/Wii-arm64 build/Wii-x86_64 -output $APP/Contents/MacOS/Wii
rm build/Wii-arm64 build/Wii-x86_64
cp -R covers $APP/Contents/Resources/
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Wii</string>
  <key>CFBundleDisplayName</key><string>Wii</string>
  <key>CFBundleIdentifier</key><string>local.wii-lanzador</string>
  <key>CFBundleExecutable</key><string>Wii</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSExceptionDomains</key><dict>
    <key>lobby.libretro.com</key><dict><key>NSExceptionAllowsInsecureHTTPLoads</key><true/></dict>
  </dict></dict>
  <key>CFBundleURLTypes</key>
  <array><dict>
    <key>CFBundleURLName</key><string>Invitación online</string>
    <key>CFBundleURLSchemes</key><array><string>wii</string></array>
  </dict></array>
</dict></plist>
PLIST
[ -f AppIcon.icns ] && cp AppIcon.icns $APP/Contents/Resources/
codesign --force --sign - $APP
rm -rf /Applications/Wii.app && cp -R $APP /Applications/
echo "Instalada en /Applications/Wii.app"
