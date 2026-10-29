#!/bin/zsh
set -euo pipefail
root=${0:A:h:h}
app=${1:-"$root/Idle Miner.app"}
identity=${IDLE_MINER_SIGN_IDENTITY:?Set IDLE_MINER_SIGN_IDENTITY to your Developer ID Application identity.}
[[ $(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist") == local.jeff.idleminer ]] || { print -u2 'Refusing to sign an unrelated app.'; exit 1; }
framework="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
for target in "$framework/XPCServices/Downloader.xpc" "$framework/XPCServices/Installer.xpc" "$framework/Updater.app" "$framework/Autoupdate" "$app/Contents/Frameworks/Sparkle.framework" "$app/Contents/Resources/miner-supervisor"; do
  /usr/bin/codesign --force --options runtime --timestamp --sign "$identity" "$target"
done
/usr/bin/codesign --force --options runtime --timestamp --entitlements "$root/macOS/MiningEngine.entitlements" --sign "$identity" "$app/Contents/Resources/xmrig"
/usr/bin/codesign --force --options runtime --timestamp --sign "$identity" "$app"
/usr/bin/codesign --verify --deep --strict "$app"
print 'Developer ID signature and nested code verification passed. This does not by itself establish notarization.'
