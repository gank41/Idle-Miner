#!/bin/zsh
set -euo pipefail
root=${0:A:h}
app="$root/Idle Miner.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$root/macOS/Info.plist" "$app/Contents/Info.plist"
/usr/bin/ditto "$root/macOS/Resources" "$app/Contents/Resources"
/usr/bin/swiftc -target arm64-apple-macos14.0 -O -module-cache-path /private/tmp/miner-swift-cache -framework AppKit -framework IOKit -framework ServiceManagement "$root"/Sources/*.swift -o "$app/Contents/MacOS/IdleMiner"
/usr/bin/clang -target arm64-apple-macos14.0 -Wall -Wextra -O2 "$root/Sources/supervisor.c" -o "$app/Contents/Resources/miner-supervisor"
/usr/bin/codesign --force --sign - "$app/Contents/Resources/miner-supervisor"
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --deep --strict "$app"
/usr/bin/plutil -lint "$app/Contents/Info.plist"
