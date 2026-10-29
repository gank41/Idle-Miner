#!/bin/zsh
set -euo pipefail
root=${0:A:h:h}
version=2.10.1
digest=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
cache="$root/Vendor/Sparkle"
archive="$root/Vendor/Sparkle-$version.tar.xz"
mkdir -p "$root/Vendor"
if [[ ! -f "$archive" ]] || [[ $(shasum -a 256 "$archive" | cut -d' ' -f1) != "$digest" ]]; then
  temporary=$(mktemp "$root/Vendor/.sparkle.XXXXXX")
  trap 'rm -f -- "$temporary"' EXIT
  curl --fail --location --retry 2 --connect-timeout 20 --max-time 600 "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" -o "$temporary"
  [[ $(shasum -a 256 "$temporary" | cut -d' ' -f1) == "$digest" ]] || { print -u2 'Sparkle archive checksum mismatch.'; exit 1; }
  mv "$temporary" "$archive"
fi
if [[ ! -f "$cache/.version-$version" ]]; then
  stage=$(mktemp -d "$root/Vendor/.sparkle-stage.XXXXXX")
  tar -xJf "$archive" -C "$stage"
  /usr/bin/codesign --verify --deep --strict "$stage/Sparkle.framework"
  [[ ! -e "$cache" ]] || mv "$cache" "$root/Vendor/Sparkle-previous-$(date +%s)"
  mv "$stage" "$cache"
  touch "$cache/.version-$version"
fi
print "Verified Sparkle $version is ready in Vendor/Sparkle."
