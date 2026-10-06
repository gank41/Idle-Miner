# Privacy and network connections

This describes Idle Miner **1.6.1 (build 9)**. Idle Miner runs locally and does not require an Idle Miner account. The app source contains no developer-operated analytics or telemetry service. Its mining and reporting features contact the third parties below; those services can observe your connection's IP address and the data sent to them.

## Wallet addresses

Idle Miner stores public native-network BTC, LTC, and DOGE Receive addresses and preferences in your user account. It does not need or store wallet passwords, private keys, or recovery phrases. A public address is not a secret key, but sharing it can reveal or link financial activity.

Saving a valid address on Mac allows the app to fetch unMineable statistics automatically, even while mining is stopped. Version 1.6.1 has no Mac reporting opt-out switch. On Linux, Settings has **Read earnings from unMineable using my public receive address**, enabled by default; turning it off disables those address/account API queries. The Linux price query still runs. Starting mining sends the selected address to the pool regardless of that reporting checkbox.

## Connections

| Service | Purpose and information sent |
| --- | --- |
| Coinbase, `api.coinbase.com` | HTTPS GET requests for the selected currency's USD spot price. The wallet address is not included in this query. |
| unMineable, `api.unmineable.com` | HTTPS GET requests containing the public Receive address and selected currency, followed by account-statistics requests using the returned account identifier. Mac also requests worker information. |
| unMineable mining pool, `rx.unmineable.com:443` | TLS-protected Stratum mining connection. The pool login contains the currency, public Receive address, and a worker label (`IdleMiner` on Mac or `IdleMinerLinux` on Linux). The engine sends accepted-work submissions and receives mining jobs. |
| XMRig donation endpoints | The engine retains its configured 1% upstream developer donation. Its source prefers `donate.ssl.xmrig.com:443` using TLS and includes a non-TLS fallback at `donate.v2.xmrig.com:3333`. The donation login uses a hash derived from the pool login. Do not assume every engine connection is encrypted. |

The reporting clients use fixed HTTPS API hosts and reject redirects. Their GET requests read provider information; the app does not use them to initiate transfers or alter provider payout settings. Reporting typically refreshes every two minutes; manual refresh is throttled. Stopping mining does not by itself stop reporting while the app stays open.

**Pool Payouts** opens a provider page in your browser with the selected public address in the URL. Help links can open other external sites. Your browser and those sites follow their own privacy behavior.

The Linux installer can contact your distribution repositories to obtain system packages. It builds the included, checksum-checked XMRig source locally. OS services, package managers, browsers, and external providers have their own policies, which this project does not control.

## Local storage and system information

Shared wallet settings are stored in `~/Library/Application Support/Idle Miner/settings.json` on Mac and `~/.config/idle-miner/settings.json` on Linux. Other app files include profile coordination metadata, engine configurations, and bounded logs. Named currency profiles have separate configurations and logs. Local session graphs are kept in memory.

The app checks input-idle time, CPU load, available memory, sleep, and available battery/thermal information to control local mining. It does not record the keys you type or their contents. A VM or unsupported desktop can expose fewer useful sensors.

Logs and engine configurations can contain public addresses, worker/account details, and machine paths. Review and redact them before attaching them to a public issue. Release installers do not include the developer's wallet settings or user mining logs.

## Your controls

- **Stop** ends mining; **Quit** ends that app instance's mining and reporting.
- Disable Linux address reporting in Settings if desired. Saving Settings stops its mining session.
- Disable **Start at Login** to prevent the default app instance from opening at login; it normally opens stopped even when enabled.
- Quit every instance before backing up or deleting local state. Removing the app does not automatically remove settings or logs.

A payout is handled by the provider and receiving wallet/exchange, not by Idle Miner. Check those services for their current privacy, payout, and deposit policies.
