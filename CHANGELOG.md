# Changes

## 1.9.1 — build 13

Successful built-in updates restore the currencies that were enabled before updating, including automatic mining temporarily paused by idle or safety conditions. Manually stopped currencies stay stopped. Normal limits and safety checks still apply; Boost and offline benchmarks are not restored. Actual sign-ins continue to follow Start at Login and its separate mining checkbox. Ordinary manual openings stay stopped. The state handoff is private, short-lived, bound to the installed location/build and consumed once.

The first transition from 1.9 may remain stopped because the older updater did not capture this state. See [release notes](docs/releases/v1.9.1.md).

## 1.9 — build 12

**Check for Updates…** now shows installed/latest versions and plain-text release notes inside the app, with **Close** and **Download and Install Now**. Mac uses Sparkle 2.10.1 with signed feeds and archives; Linux verifies the signed manifest and archive and builds a staged replacement before stopping the installed copy. Installation preserves wallet settings and reopens stopped. Checks run only when requested.

Version 1.8 and earlier need one manual install of 1.9 to gain built-in installation. See the [1.9 release notes](docs/releases/v1.9.md) for verification limits.

## 1.8 — build 11

The website, installers, corresponding source downloads, and update information now live at [idleminer.app](https://idleminer.app/) on Cloudflare Pages. The GitHub repository remains available for source and issues.

Currency instances now share one menu bar icon on Mac and one tray icon on Linux and a manual **Check for Updates…** command. A check offers release notes and the matching installer; users install updates themselves after quitting every currency instance. Wallet addresses and mining settings are not included in update requests.

See the [release notes](docs/releases/v1.8.md) for downloads and verification limits.

## 1.7 — build 10

Added Ethereum (ETH) payout addresses, mixed-case EIP-55 checksum validation, ETH reporting and currency profiles. Mining remains CPU RandomX through unMineable; Ethereum is not mined directly. Confirm the provider payout network matches the receiving wallet's ETH network.

Added **Start at Login and Start Mining configured currencies**, off by default beneath Start at Login. With both enabled, actual login launches start each valid saved currency within the shared CPU limit and safety checks. Manual openings and Start at Login alone remain stopped. Turning off Start at Login clears the mining opt-in.

See the [release notes](docs/releases/v1.7.md) for downloads and current verification limits.

## 1.6.1 — build 9

Mining Stats opens larger and can be resized. Mac Stats remembers its chosen size while the app remains open. Scrolling remains available on smaller screens.

See the [release notes](docs/releases/v1.6.1.md) for downloads and platform verification limits.

## 1.6 — build 8

Added saved BTC/LTC/DOGE wallets, currency switching, separate currency instances sharing a CPU limit, Dock/taskbar and menu bar/tray visibility, and session/uptime clocks. Improved coordination and thread changes between instances.

## Earlier releases

Introduced automatic idle-aware mining, timed Boost, status colors, mining and provider statistics, login controls, and Mac/Linux distribution packages.
