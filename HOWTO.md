# Install and use Idle Miner

Idle Miner uses spare CPU time to run the RandomX mining algorithm. unMineable handles the pool work and conversion into your chosen payout currency: Bitcoin (BTC), Litecoin (LTC), or Dogecoin (DOGE). Choosing BTC does not turn your CPU into a Bitcoin ASIC miner; it chooses how the provider accounts for and pays your rewards.

A public **Receive address** tells the provider where to send a payout. Idle Miner never needs a wallet login, password, recovery phrase, or private key. Mining uses electricity and produces heat; earnings are variable and may be lower than your costs.

## Download

Get the current packages from [GitHub Releases](https://github.com/gank41/Idle-Miner/releases). For version **1.6.1 (build 9)**, choose:

| Computer | Download |
| --- | --- |
| Apple Silicon Mac, macOS 14 or later | `Idle-Miner-1.6.1-macOS.dmg` |
| Supported 64-bit ARM or x86 Linux desktop | `Idle-Miner-1.6.1-Linux.tar.gz` |

The Linux download is a source installer that builds the engine on your computer. It needs Python/PySide6, Qt 6, KDE Frameworks 6 development packages, and compiler dependencies from your distribution repositories. Fedora, Fedora Asahi, and recent Ubuntu/Debian-family systems are supported by the installer; older releases may lack the required packages. Native Asahi operation has not been verified. See the [release notes](docs/releases/v1.6.1.md) for testing details.

## Install on a Mac

1. If updating, select **Stop** and **Quit** in **every** Idle Miner currency instance before replacing the app.
2. Open `Idle-Miner-1.6.1-macOS.dmg`.
3. Drag **Idle Miner** into **Applications**. Replace the previous copy if updating.
4. Eject the mounted disk and open **Idle Miner** from Applications.

Existing wallets and settings remain in your user account. The app normally opens stopped. Open any additional currency instances again and start them when ready.

This build is locally **ad-hoc signed**, and **has not been notarized by Apple**. macOS may block the first launch because it cannot verify the developer or check the app for malicious software. Only proceed if you trust the source and the downloaded app. After trying to open it, Apple's documented process is **System Settings → Privacy & Security → Open Anyway**, then confirm **Open** if that option is available. Read [Apple's instructions and warnings](https://support.apple.com/en-us/102445) first. A warning that the app is damaged or will harm your computer requires investigation before opening it.

## Install on Linux

1. If updating, stop mining and quit **all** Idle Miner windows/profiles.
2. Extract `Idle-Miner-1.6.1-Linux.tar.gz`.
3. Open Terminal in the extracted `Idle-Miner-1.6.1-Linux` folder.
4. Run:

   ```sh
   bash install.sh
   ```

5. Allow several minutes for the build, then open **Idle Miner** from your application launcher.

Run the installer as your normal desktop user. It requests `sudo` only to install missing system dependencies; do not run the whole installer with `sudo`. Internet access is needed for those packages. The pinned XMRig source is included and checked before building. If your package manager is busy updating the OS, let that update finish and retry. Existing settings are preserved during reinstall.

## Set up a payout address

1. In a compatible wallet or exchange account, open **Receive** for the currency you want.
2. Copy that currency's public address on its **native network**. Check that the destination supports receiving that currency and any deposit requirements.
3. Open Idle Miner **Settings** and paste the address into its matching BTC, LTC, or DOGE field. Leave currencies you do not plan to use blank.
4. Choose the currency for this instance and save. Check the saved address against your wallet's Receive screen.
5. Select **Start Mining**.

Saving Settings stops this instance's mining session. Start it again when you are ready. See [Privacy](PRIVACY.md) before saving an address: reporting sends your public address to unMineable, and mining sends it in the pool login. The Mac reports automatically while open; Linux offers a reporting checkbox.

## Daily controls

| Control | What happens |
| --- | --- |
| **Start Mining** | Enables automatic mining: lighter CPU use while you are active, more after five minutes idle. Settings can pause completely while active. |
| **Stop** | Ends the session and cancels a timed Boost. |
| **Boost** | Temporarily uses the shared configured CPU limit for 15/30 minutes or 1/6/12/24 hours, then returns to automatic mode. Safety checks still apply. |
| **End Boost** | Returns to automatic mode before the timer expires. |
| **Offline Test** | Runs a short local one-thread test without connecting to a mining pool or earning rewards. |

Battery, heat, memory pressure, sustained CPU load, and system sleep can pause or reduce work. Idle Miner does not change sleep settings or keep the computer awake. Display sleep is different from system sleep: mining can continue while the display is off if the system remains awake. In a VM, guest activity and available sensors may not reflect the host; use modest CPU/RAM allocations and stop if responsiveness suffers.

The status color describes operation: **green** means confirmed work, **gray** means stopped, paused, or starting, and **red** means an engine, connection, or reporting issue. A working Offline Test is labeled as earning nothing. Green does not promise a payout or profit.

## Switch or run multiple currencies

Use **Switch Currency** to choose another saved address in the same instance. The old engine stops before the new one starts. If the session was running, automatic mining may resume for the new currency. A missing address opens Settings and leaves mining stopped.

Use **Open Another Currency** for a separate instance. It opens **stopped**: check its wallet and start it explicitly. Each instance has its own Stats, engine configuration, and logs. Only one engine may mine a given currency at a time.

All instances for the same OS user **share the total configured CPU/thread limit**. Opening a second currency does not double that limit. Capacity becomes available to other instances after an engine has actually stopped. Each engine needs its own RandomX dataset of roughly 2 GB; Linux checks for at least 3 GB of free memory before starting an engine. Additional currencies need additional memory.

## Read Mining Stats

| Item | Meaning |
| --- | --- |
| **Hashrate and graph** | Locally observed computing speed and recent session history. Gaps can reflect pauses, startup, or unavailable readings. |
| **Accepted shares** | Work accepted by the pool during this local session. They are not payments or a guarantee that all computation earned a reward. |
| **Pool balance** | The provider's reported unpaid balance for this currency/address. It can include other devices and earlier sessions. |
| **Worker status** | Provider-reported activity; where available it can include multiple workers using the address, and can lag local work. |
| **Coin price** | A Coinbase USD spot quote, not a profit calculation. Electricity costs are not deducted. |
| **Session began / elapsed** | Start date/time and elapsed session time, including automatic pauses. Elapsed time freezes on Stop; the next Start begins a new session. |
| **Hashing time** | Sampled time with fresh positive work, excluding startup and long sleep gaps. It is not a precise measure of total CPU work. |
| **App uptime** | Time this app instance has remained open. |

Pool reporting and prices may be delayed or unavailable. A failed query is not proof of a zero balance. Use **Pool Payouts** to inspect the provider's dashboard and current threshold, fees, payout settings, and any reported issue.

The provider sends a payout only when its current rules and configured payout settings allow it. Idle Miner does not transfer funds or change those settings. Check your wallet or exchange separately to confirm a deposit; pool credit or a payout status is not the same as a confirmed wallet receipt. There is no fixed earnings or payout-time promise.

Mining Stats can be resized by dragging an edge or corner. Small displays retain scrolling. On Mac, reopening Stats during the same app session preserves your chosen size.

## Visibility and login

On Mac, Settings lets you show a Dock icon, a menu bar icon, or both. The menu bar is the default. Keep at least one visible.

On Linux, these options control the main window/taskbar and tray presence. A desktop without a usable tray keeps the main window accessible. Closing hides the window only when a usable visible tray remains; otherwise it quits and stops mining. GNOME tray support depends on the desktop setup.

**Start at Login** opens the default instance stopped. Additional currency instances must be opened and started separately.

## Keep or remove your settings

Updates preserve the settings stored outside the app:

- macOS: `~/Library/Application Support/Idle Miner/settings.json`.
- Linux: `~/.config/idle-miner/settings.json`.

Quit every instance before backing up or changing these files. Settings, configuration, and logs can contain your public wallet addresses; do not post them unredacted.

To remove the app, first turn off **Start at Login** and quit every instance. On Mac, remove Idle Miner from Applications; keep or remove its Application Support folder separately. On Linux, the installed app is in `~/.local/share/idle-miner`, its launcher is `~/.local/bin/idle-miner`, and its desktop entry is `~/.local/share/applications/idle-miner.desktop`. Keep or remove the settings directory separately. Do not delete coordination locks while any instance is running.

For problems, include your OS, app version, and a description in a [GitHub issue](https://github.com/gank41/Idle-Miner/issues). Redact public addresses and other personal information from logs and screenshots first.
