#!/bin/zsh
set -euo pipefail
root=${0:A:h}
app="$root/Idle Miner.app"
zsh "$root/tools/fetch-sparkle.sh"
mkdir -p "$app/Contents/Frameworks"
/usr/bin/ditto "$root/Vendor/Sparkle/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$root/macOS/Info.plist" "$app/Contents/Info.plist"
/usr/bin/ditto "$root/macOS/Resources" "$app/Contents/Resources"
/usr/bin/swiftc -target arm64-apple-macos14.0 -O -module-cache-path /private/tmp/miner-swift-cache -framework AppKit -framework IOKit -framework ServiceManagement -F "$root/Vendor/Sparkle" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks "$root"/Sources/*.swift -o "$app/Contents/MacOS/IdleMiner"
/usr/bin/clang -target arm64-apple-macos14.0 -Wall -Wextra -O2 "$root/Sources/supervisor.c" -o "$app/Contents/Resources/miner-supervisor"
/usr/bin/codesign --force --sign - "$app/Contents/Resources/miner-supervisor"
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --deep --strict "$app"
/usr/bin/plutil -lint "$app/Contents/Info.plist"
if [[ -n ${IDLE_MINER_SIGN_IDENTITY:-} ]]; then
 zsh "$root/tools/sign-mac-release.sh" "$app"
fi
