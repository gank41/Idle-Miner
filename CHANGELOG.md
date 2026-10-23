# Changes

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
