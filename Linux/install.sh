#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
if [[ $(uname -s) != Linux || ! -f /etc/os-release ]]; then echo 'Run this installer inside Fedora, Fedora Asahi, Ubuntu or Debian Linux.'; exit 1; fi
if [[ $EUID == 0 ]]; then echo 'Run as your normal desktop user, not with sudo. The installer asks for sudo only for dependencies.'; exit 1; fi
if [[ $(uname -m) != aarch64 && $(uname -m) != x86_64 ]]; then echo 'A 64-bit ARM or x86 Linux system is required.'; exit 1; fi
source /etc/os-release
printf '%s\n' 'Installing Idle Miner 1.6.1 (build 9) for this user. Mining never starts automatically.'
case " $ID ${ID_LIKE:-} " in
 *fedora*)
  packages=(python3-pyside6 gcc gcc-c++ libstdc++-static cmake make libuv-devel openssl-devel hwloc-devel kf6-kidletime-devel qt6-qtwayland)
  if ! rpm -q "${packages[@]}" >/dev/null 2>&1; then sudo dnf install -y "${packages[@]}"; fi
  ;;
 *ubuntu*|*debian*)
  packages=(python3-pyside6.qtwidgets python3-pyside6.qtdbus python3-pyside6.qtnetwork build-essential cmake libuv1-dev libssl-dev libhwloc-dev libkf6idletime-dev qt6-wayland)
  missing=false
  for package in "${packages[@]}"; do [[ $(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null || true) == installed ]] || missing=true; done
  if $missing; then sudo apt-get update; sudo apt-get install -y "${packages[@]}"; fi
  ;;
 *) echo 'Supported distributions: Fedora / Asahi and Ubuntu / Debian family.'; exit 1;;
esac
printf '%s\n' '5005144e78571f26586410c2b2ede2b0c72afe22f97f1708ea24cfb253c3939b  vendor/xmrig-6.26.0.tar.gz' | sha256sum -c -
build_dir=$(mktemp -d)
trap 'rm -rf -- "$build_dir"' EXIT
tar -xzf vendor/xmrig-6.26.0.tar.gz -C "$build_dir"
cmake -S "$build_dir/xmrig-6.26.0" -B "$build_dir/xmrig-build" -DCMAKE_BUILD_TYPE=Release -DWITH_OPENCL=OFF -DWITH_CUDA=OFF -DWITH_MSR=OFF -DWITH_HTTP=OFF -DCMAKE_EXE_LINKER_FLAGS=-Wl,-z,max-page-size=16384
cmake --build "$build_dir/xmrig-build" -j2
cmake -S idle-helper -B "$build_dir/idle-build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$build_dir/idle-build" -j2
cc -Wall -Wextra -O2 supervisor.c -o "$build_dir/miner-supervisor"
IDLE_MINER_SUPERVISOR="$build_dir/miner-supervisor" python3 -m unittest discover -s tests -v
# Hold the same lock as the app before replacing any installed files.
export IDLE_MINER_BUILD="$build_dir"
python3 install_files.py
printf '\n%s\n' 'Installed. Open Idle Miner from your application launcher, then Settings.' 'You can delete this extracted installer folder; keep the original archive to reinstall.'
