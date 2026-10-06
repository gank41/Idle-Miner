IDLE MINER 1.6.1 (BUILD 9) FOR LINUX
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
Mining never starts merely by installing, launching or Start at Login.

SETTINGS
Save public RECEIVE addresses for BTC, LTC and DOGE together. Use each
currency's native network. Never enter a seed phrase, private key or
password. Existing saved currency/address settings are retained.
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
only when a visible usable tray exists; otherwise closing quits and stops
mining. The tray symbol is green for fresh work, red for an engine,
connection or reporting issue, gray for stopped/paused/starting. GNOME may
need a tray extension; the regular window works without one.
Start at Login launches the default profile stopped. The offline test uses
one thread for up to 70 seconds, connects to no pool and earns nothing.

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
