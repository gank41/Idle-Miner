<p align="center">
  <a href="https://idleminer.app/">
    <img src="docs/assets/idle-miner.png" alt="Idle Miner: a computer with a Bitcoin symbol and a crescent moon" width="144" height="144">
  </a>
</p>

<h1 align="center">Meet Idle Miner...</h1>

<p align="center">
  <strong>A small desktop app that puts spare computing time to work.</strong><br>
  Mine with RandomX, and choose payouts in Litecoin, Dogecoin, Bitcoin or Ethereum through unMineable.
</p>

<p align="center">
  Apple Silicon Macs &amp; 64-bit Linux · Free and open source · GPL-3.0<br>
  <sub>By Jeffry Zander</sub>
</p>

<p align="center">
  <a href="https://idleminer.app/#downloads"><strong>Get Idle Miner ↓</strong></a>
  &nbsp; · &nbsp;
  <a href="https://idleminer.app/guide.html">Setup guide</a>
  &nbsp; · &nbsp;
  <a href="https://idleminer.app/releases/">Release notes</a>
  &nbsp; · &nbsp;
  <a href="https://idleminer.app/">Website ↗</a>
</p>

---

<p align="center">
  <strong>Less CPU while you work &nbsp; · &nbsp; Shared limits across currencies &nbsp; · &nbsp; Opens stopped by default</strong>
</p>

## Your computer does the work. You stay in control.

Mining means using your CPU to perform calculations for a cryptocurrency network. Idle Miner runs XMRig's RandomX / Monero engine; unMineable converts credited work into your selected payout currency. Choosing BTC or ETH selects the payout currency—it does not change the mining algorithm to Bitcoin or Ethereum.

| 01 · Set it, then start it | 02 · Give your work room | 03 · See what's happening |
| --- | --- | --- |
| Save a public Receive address, choose a currency, and select **Start Mining**. Manual openings stay stopped. | Automatic mode uses one thread while you're active and increases after five minutes idle. You can choose to pause completely while active. | Mining Stats brings local work, provider balance, and payout progress together. Accepted shares are pool work; the provider handles wallet payments. |

## Make it yours

Current release: **1.9.3 · Build 15** · [What's new](docs/releases/v1.9.3.md)

| | macOS | Linux |
| --- | --- | --- |
| **Download** | **[Download for Mac ↓](https://idleminer.app/downloads/v1.9.3/Idle-Miner-1.9.3-macOS.dmg)** | **[Download for Linux ↓](https://idleminer.app/downloads/v1.9.3/Idle-Miner-1.9.3-Linux.tar.gz)** |
| **Your computer** | Apple Silicon · macOS 14 or later | 64-bit ARM64 or x86_64 · supported desktop distribution |
| **Install** | Open the DMG and drag Idle Miner to Applications. | Extract the archive, open Terminal in its folder, and run `bash install.sh` as your desktop user. |
| **At a glance** | Native Mac app, menu bar controls, optional Dock icon, resizable Mining Stats. | Fedora, Fedora Asahi, Ubuntu and recent Debian-family desktops with the required packages. |

The Mac release is Developer ID signed with hardened runtime. See [release verification notes](docs/releases/v1.9.3.md) for notarization and platform coverage. There is no Intel Mac installer in this release.

Linux builds locally and needs internet for dependencies. The installer may request sudo for system packages; Qt 6 / PySide6 and KDE Frameworks 6 development packages must be available. Older distributions may lack them. Native Asahi hardware operation remains unverified.

[Installation help](HOWTO.md) · [SHA-256 checksums](https://idleminer.app/downloads/v1.9.3/SHA256SUMS.txt) · [Matching source archive](https://idleminer.app/downloads/v1.9.3/Idle-Miner-1.9.3-source.tar.gz)

## Small app. Useful controls.

| Feature | What you can do |
| --- | --- |
| **Four payout currencies** | Save separate public Receive addresses for **LTC · DOGE · BTC · ETH**. Switch currency or open another currency instance. |
| **One menu bar / tray icon** | Open each currency's submenu for its stats and controls. Green means fresh work, red means an issue, and gray means paused, starting or stopped. |
| **A shared CPU budget** | Running currencies share the configured thread limit. Battery, heat, memory pressure and sustained CPU load can pause or reduce mining; sensor availability varies. |
| **Timed Boost** | Try 15 or 30 minutes, or 1, 6, 12 or 24 hours. When the timer ends, return to automatic mode. |
| **Mining Stats** | See recent hashrate, accepted/rejected shares, session start date, elapsed time, hashing time, app uptime, coin price and provider payout progress. |
| **Your choice at login** | Start at Login opens stopped. A separate, default-off option can start your configured currencies at actual login. |
| **Updates on your terms** | Review versions and release notes, then choose **Download and Install Now**. Optional Daily or Weekly checks can notify you; installation remains your choice. |

Each running currency needs its own roughly 2 GB RandomX dataset. More currencies need more memory, and the app can wait for sufficient free memory before starting. Idle Miner does not prevent system sleep.

## Start with the basics

1. **Install** the package for your computer.
2. **Open Settings** and paste your chosen currency's public **Receive address**, on its native network. Never enter a password, private key or recovery phrase.
3. **Choose Start Mining**, then open Mining Stats to see local work and provider reporting.

You can also run the one-thread **Offline Test** for up to 70 seconds without a wallet or pool connection. It checks local hashing and earns nothing.

## A few things worth understanding

<details>
<summary><strong>How do payments reach my wallet?</strong></summary>

Your public Receive address tells unMineable where to send the selected coin. The provider records rewards in its pool balance. Automatic payouts happen only when configured with the provider and its current threshold and rules are met.

Use **Pool Payouts** to check the provider dashboard. Idle Miner does not transfer funds, change provider payout settings or guarantee a payment schedule. Check the receiving wallet separately to confirm a deposit.

</details>

<details>
<summary><strong>What do the Stats numbers mean?</strong></summary>

- **Hashrate:** the speed of mining calculations.
- **Accepted shares:** work the pool accepted, rather than deposits in your wallet.
- **Pool balance:** rewards accounted for by the provider; reporting and prices can lag.
- **Session runtime:** elapsed session time, including automatic pauses; it freezes when you stop.
- **Hashing time:** observed positive work, excluding pauses and long gaps.
- **App uptime:** how long that currency's app instance has been open.

A new Start begins a new session. Each currency has separate accounting. Estimated values do not deduct electricity.

</details>

<details>
<summary><strong>Which wallets and networks can I use?</strong></summary>

Use a public Receive address on the selected coin's **native network**, from a compatible wallet or exchange. Wrapped coins and addresses for a different currency are not interchangeable. Bitcoin Lightning and Taproot, and Litecoin MWEB addresses are not supported by this build.

For ETH, confirm **Ethereum** as the payout and receiving network. A `0x` address alone cannot identify its network; mixed-case addresses must pass EIP-55 validation. Ethereum uses proof of stake—Idle Miner performs RandomX work, and the provider converts the credited rewards to ETH. See [Ethereum setup](HOWTO.md#ethereum-payouts).

</details>

<details>
<summary><strong>Can it stay out of the way and start at login?</strong></summary>

On Mac, menu-bar-only is the default. Choose a Dock icon, a menu bar icon or both in Settings. On Linux, choose window/taskbar and tray visibility; a desktop without a usable tray keeps the window available. Keep at least one visibility option enabled.

**Start at Login** alone opens stopped. The separate **Start at Login and Start Mining configured currencies** checkbox is off by default. Enable both to start every valid saved currency at actual login, within the shared CPU and safety limits. Manual openings stay stopped. Turning Start at Login off also clears its mining opt-in.

</details>

<details>
<summary><strong>How do updates work?</strong></summary>

Choose **Check for Updates…** to compare your version with the latest release. Release notes stay collapsed when you're current and open for available updates. Choose **Close** or **Download and Install Now**.

Authenticated updates replace the app in its existing location and preserve saved wallets and settings. Updates initiated by 1.9.1 or later restore previously enabled currencies, within normal idle and safety limits; manually stopped currencies remain stopped. The older 1.9 updater may reopen stopped for its first transition. On Mac, choosing installation stops mining before downloading; cancelling afterward leaves it stopped.

Optional **Daily** or **Weekly** checks run while the app is open and can notify you when an update is available. They are off by default and never install automatically. Version 1.8 and earlier need one manual installation of the current release to gain built-in updates.

</details>

Mining uses electricity and can increase heat and fan activity. Rewards vary with hardware, pool conditions and coin prices, and may not cover costs. XMRig retains its normal 1% developer donation; provider fees, thresholds and payout rules also apply. No earnings are promised.

## Free software, with the source included

Idle Miner is **free and open source under GPL-3.0**. Inspect it, build it, modify it and share it under the license terms. XMRig 6.26.0's corresponding source is included in `Linux/vendor/` and release packages.

[Build from source](BUILDING.md) · [GPL-3.0 license](LICENSE) · [Privacy](PRIVACY.md) · [Third-party notices](THIRD-PARTY-NOTICES.md)

For problems or suggestions, [open an issue](https://github.com/gank41/Idle-Miner/issues) with your OS, app version and symptoms. Redact wallet addresses, balances and personal paths from logs or screenshots.

---

<p align="center">
  <strong>Your computer. Your call.</strong><br>
  Choose a platform, read the guide, and start when you're ready.<br><br>
  <a href="https://idleminer.app/">idleminer.app</a> · By Jeffry Zander
</p>

<sub>Copyright © 2026 Jeffry Zander. Independent of the pool, wallet providers, Apple, Qt, KDE and XMRig.</sub>
