# Idle Miner

**Use spare CPU time, with controls that keep your computer usable.**

Idle Miner is a desktop app by Jeffry Zander for Apple Silicon Macs and supported Linux desktops. It runs XMRig’s RandomX engine through unMineable, which accounts for rewards in your selected payout currency: **Bitcoin, Litecoin, or Dogecoin**. Selecting Bitcoin chooses the payout currency; this is not direct Bitcoin ASIC mining.

[Website](https://gank41.github.io/Idle-Miner/) · [Download releases](https://github.com/gank41/Idle-Miner/releases) · [Simple how-to](HOWTO.md) · [Privacy](PRIVACY.md)

## Download and install

Current release: **1.6.1 (build 9)**.

| Platform | Package | Install |
| --- | --- | --- |
| Apple Silicon, macOS 14+ | [Mac DMG](https://github.com/gank41/Idle-Miner/releases/download/v1.6.1/Idle-Miner-1.6.1-macOS.dmg) | Open the disk image and drag Idle Miner to Applications. |
| Supported ARM64/x86_64 Linux desktop | [Linux installer](https://github.com/gank41/Idle-Miner/releases/download/v1.6.1/Idle-Miner-1.6.1-Linux.tar.gz) | Extract and run `bash install.sh` as your desktop user. |

The Mac app is locally ad-hoc signed and **not Apple-notarized**. Read the [Mac installation instructions](HOWTO.md#install-on-a-mac) before opening it. There is no Intel Mac package in this release.

The Linux installer builds locally and needs distribution-provided Qt 6, PySide6, KDE Frameworks 6, and compiler dependencies. Fedora/Fedora Asahi and recent Ubuntu/Debian-family distributions are supported by the installer when those packages are available. Native Asahi and the Linux 1.6.1 GUI have not been directly verified; see the [release testing notes](docs/releases/v1.6.1.md).

## What you can control

- Automatic mining uses fewer threads while you work, then increases after five minutes idle. You can choose to pause completely while active.
- Timed Boost runs for 15 or 30 minutes, or 1, 6, 12, or 24 hours, then returns to automatic mode.
- Save separate BTC, LTC, and DOGE public Receive addresses. Switch currency or open a second instance; all instances share the configured CPU limit.
- Mining Stats shows a recent hashrate graph, accepted/rejected shares, session date and elapsed time, hashing time, app uptime, coin price, and provider balance/payout progress.
- Choose menu bar/tray and Dock/taskbar visibility. Start at Login opens the default instance stopped.
- Battery, heat, memory pressure, and CPU-load checks can pause or reduce mining. The app does not prevent system sleep.

Each mining instance needs its own roughly 2 GB RandomX dataset. Multiple currencies need more memory. Sensor availability varies, especially in VMs.

## Start simply

1. Install the matching package.
2. Copy your chosen currency’s **native-network Receive address** from a compatible wallet or exchange into Settings. Never enter a password, private key, or recovery phrase.
3. Start mining, then open Mining Stats to see local work and provider reporting.

Accepted shares are work accepted by the pool, **not wallet payments**. The provider’s current threshold, fees, and payout settings determine when funds are sent. Check the receiving wallet separately to confirm a deposit. Mining uses electricity and may cost more than it earns; no earnings or payout schedule is promised.

The [how-to](HOWTO.md) explains setup, everyday controls, multiple currencies, payouts, updates, and removal. [Privacy](PRIVACY.md) describes address reporting and network connections. Mac reporting runs automatically while the app is open; Linux has a reporting checkbox.

## Source, feedback, and licenses

See [BUILDING.md](BUILDING.md) for a fresh source build and tests. Original Idle Miner application source is **GPL-3.0**; [LICENSE](LICENSE) and [third-party notices](THIRD-PARTY-NOTICES.md) describe redistribution and dependency terms. XMRig 6.26.0’s matching upstream source is included in `Linux/vendor/`.

For problems, [open an issue](https://github.com/gank41/Idle-Miner/issues) with your OS, app version, and symptoms. Redact wallet addresses, balances, and personal paths from logs or screenshots before posting.

Copyright © 2026 Jeffry Zander. This project is independent of the pool, wallet providers, Apple, Qt, KDE, and XMRig.
