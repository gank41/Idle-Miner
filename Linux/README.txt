IDLE MINER 1.9.2 (BUILD 14) FOR LINUX
By Jeffry Zander

INSTALL
Boot Fedora / Fedora Asahi, Ubuntu or a recent Debian-family desktop.
Extract the Linux installer archive, open Terminal in that folder and run:
    bash install.sh
Run as your normal user. Enter your password if sudo asks to install
system packages. Internet is needed for packages; the checksum-verified
XMRig 6.26.0 engine source is included. Builds use two threads and take
several minutes. Open Idle Miner from your application launcher.
Qt 6 / PySide6 and KDE Frameworks 6 development packages must be available
in your distribution repositories. Ubuntu 26.04 ARM64 dependency names
were checked on an actual guest. Older releases may lack these packages.
Installing and manual launches open stopped. Start at Login also opens
stopped unless you explicitly enable the separate login mining option.

SETTINGS
Save public RECEIVE addresses for BTC, LTC, DOGE and ETH together. Use each
currency's native network. Never enter a seed phrase, private key or
password. ETH payouts use Ethereum (ETH): select that same network at
unMineable and in your wallet. A 0x address cannot identify its network.
ETH addresses accept uniform case or a valid mixed-case EIP-55 checksum;
zero addresses and payment URIs are rejected. Existing wallets are retained.
Switch Currency stops/reaps the engine and resets the displayed stats.
A running session resumes with the saved target address, or opens Settings
if no target address is saved. Open Another Currency launches another
window with separate engine configuration and logs. One engine per
currency is allowed; duplicate profile launches focus the existing window.
Changing a running profile's address in another window stops that session.
Stale settings dialogs merge only wallet/preference entries you changed.

RUNNING
Start enables automatic mining: one thread while active, increasing after
five minutes idle. Settings can pause completely while active. Boost runs
for the selected time then returns to automatic. All currency windows
SHARE the maximum idle / boost thread setting. Two CPU cores are reserved
where possible. A new miner waits for an existing engine to actually
release capacity. A crashed controller's supervisor reaps its engine before
its reservation is released. Each RandomX dataset needs at least 3 GB
free memory to start; additional currencies need additional memory.
Battery, heat, memory pressure and sustained CPU load can pause/back off
mining. Thread changes reuse the running dataset; unexpected engine
counts or an unconfirmed change stop mining safely.

Stats include local session start date/time, session runtime (frozen on
Stop), app uptime and hashing time. Hashing time counts fresh positive
hashrate after startup and excludes long sleep gaps; it is sampled, not a
precise meter of CPU work. Session runtime continues during automatic
pauses. Accepted shares are work accepted by the pool, not payments. Only pool balance
confirms accounted rewards. Pool price/earnings can lag actual mining;
electricity cost is not deducted. Pool Payouts opens the provider dashboard.
The app never transfers funds or changes provider payout settings.

VISIBILITY
Settings offers window / taskbar and tray / menu bar switches. Keep at
least one selected. Linux defaults to both. If the desktop has no usable
tray, the window always remains visible and explains why. Closing hides
only when the shared usable tray exists; otherwise closing quits and stops
mining. All current currency profiles share one Bitcoin tray symbol. Hover
a currency row for its summary, stats and controls. Row symbols are green
for fresh work, red for an engine, connection or reporting issue, and gray
for stopped/paused/starting or stale reports. Configured currencies that
are not running can be opened stopped. Quit This Currency leaves other
profiles running; Quit Idle Miner asks every current profile to quit. A
remaining profile takes over if the tray owner quits or crashes. Older
versions must be quit and updated to remove their separate icons. GNOME may
need a tray extension; the regular window works without one.
Start at Login launches the default profile stopped by default. Directly
below it, "Start at Login and Start Mining configured currencies" is an
optional, initially OFF checkbox. It is enabled only while Start at Login
is enabled. Both controls take effect immediately; turning Start at Login
off also clears this opt-in. With both enabled, an actual login launch
starts one miner per currency with a valid saved wallet (BTC/LTC/DOGE/ETH).
Currencies with blank wallets are skipped, without opening Settings. All
miners keep the same shared CPU and memory rules. Manual application
launches stay stopped. Reinstall updates an existing autostart entry and
preserves its enabled/disabled state; it does not enable autostart.
The offline test uses
one thread for up to 70 seconds, connects to no pool and earns nothing.

UPDATES
Check for Updates shows the installed and latest versions and status. When
up to date, optional Release Notes start collapsed; click to expand or hide
them. Notes stay hidden while checking or after an error. A newer signed
release shows its notes expanded and offers Download and Install Now. This
downloads and verifies the signed release, then prepares a native Linux build
in a private folder.
This can take several minutes. Close cancels preparation. If development
packages are missing, it explains how to install them in a terminal while
leaving the current app running; the updater never asks for hidden sudo.

After preparation, all currencies stop and quit gracefully. The updater waits
for every mining supervisor to finish and replaces the app in its existing
folder. After a successful update, each previously open currency returns to its
exact enabled or stopped state. Enabled currencies use their normal idle and
safety settings, including any automatic pause; manually stopped currencies
stay stopped. Boost and offline benchmarks do not resume. Wallets, settings,
logs, desktop entries, and login preferences stay in place. The previous app
folder is retained beside the installation for recovery; a failed replacement
restores it and does not resume mining. A busy app or engine prevents replacement.

The update from 1.9 to 1.9.1 uses the old updater, which cannot capture currency
states, so that first transition reopens stopped. Automatic restoration applies
to subsequent successful updates initiated by 1.9.1 or later. Manual launches
without a valid update receipt stay stopped. Actual OS login follows the
separate Start at Login and Start Mining preference in Settings.

Update checks contact https://idleminer.app/updates/stable.json and its
Ed25519 signature only when requested, at most once every 30 seconds. The
release signature, exact archive length, and SHA-256 checksum are verified
before any downloaded installer code runs. Release notes display as plain
text. Unsigned, modified, and older releases cannot be installed.

LINUX / ASAHI / VM NOTES
Uses GNOME Mutter idle monitoring or KDE KIdleTime. KDE detection stays
unconfirmed until the first idle event; unsupported desktops stay light.
The engine is compiled locally for x86_64 or ARM64, with 16 KB-compatible
ELF alignment for Asahi. Native Asahi hardware/kernel operation is not
verified; try the offline test first. True system sleep suspends mining;
display sleep is fine while the system stays awake. No sleep settings are
changed. VMs cannot read host battery/temperature/activity. Keep the host
plugged in and use modest guest CPU/RAM allocations. Guest idle can mine
while the host is active. Stop if that affects responsiveness.

REINSTALL / REMOVE
Quit ALL currency windows before reinstalling. The installer protects all
profile and engine locks; it does not replace live executable files.
Your shared settings remain in ~/.config/idle-miner/settings.json.
Default config/logs retain that directory; named currency config/logs are
under ~/.config/idle-miner/profiles/COIN. Stable locks and private quota
metadata stay at the shared root; do not delete locks while any app runs.
App: ~/.local/share/idle-miner. Launcher: ~/.local/bin/idle-miner.
To remove: turn off Start at Login, quit all windows, then remove those
paths and ~/.local/share/applications/idle-miner.desktop. Settings/logs
may be kept or removed separately. No privileged mining service is used.
Wallets/settings/logs are not included in the installer archive.

SOURCE AND LICENSES
All app source is included, together with XMRig 6.26.0 source and GPL-3.0
licenses. Installed copies retain source too. XMRig keeps its normal 1%
developer donation; pool fees/thresholds are set by the provider.
https://github.com/xmrig/xmrig/tree/v6.26.0
https://api.kde.org/kidletime-index.html
https://asahilinux.org/fedora/

WINDOWS (1.6.1)
Mining Stats opens larger, fits the available desktop, and remains resizable.
Drag a window edge to resize. Scrolling remains available on smaller displays.
