# Idle Miner website and downloads

The production site is https://idleminer.app/, served by the **idle-miner** Cloudflare Pages project. Deployments are direct uploads of static files. The GitHub repository holds source and public documentation; it does not build or serve this website. Release binaries and staging output stay outside Git. This setup uses Pages static hosting; no R2 bucket, Worker, server or paid add-on is required.

Use Node.js 20 or later. Install the pinned Markdown renderer once:

```sh
npm install --prefix Deployment
```

Prepare an audited release directory containing the Mac DMG, Linux source installer, corresponding source archive, `Idle-Miner-How-To.md`, `LICENSE.txt` and `SHA256SUMS.txt`. The names must match the version in the update manifest. The manifest uses:

```json
{
  "schemaVersion": 1,
  "version": "1.8",
  "build": 11,
  "releaseNotesURL": "https://idleminer.app/releases/v1.8.html",
  "platforms": {
    "macos": { "url": "https://idleminer.app/downloads/v1.8/Idle-Miner-1.8-macOS.dmg", "sha256": "SHA256_OF_DMG" },
    "linux": { "url": "https://idleminer.app/downloads/v1.8/Idle-Miner-1.8-Linux.tar.gz", "sha256": "SHA256_OF_LINUX_ARCHIVE" }
  }
}
```

Build into a **new directory outside the repository** (replace the example paths with the prepared release and manifest):

```sh
node Deployment/build-site.mjs \
  --release-dir /path/to/release \
  --manifest /path/to/stable.json \
  --output /tmp/idleminer-site-v1.8
```

The builder copies only public site assets, renders the public guides and release notes, checks installer URLs and SHA-256 hashes against the manifest, requires checksum coverage for every distributed asset, and rejects files at or above Pages' 25 MiB per-file limit. It does not copy the repository, Audit, runtime state, wallets or logs. Keep release URLs immutable; publish changed bytes under a new version. The update manifest is served with `Cache-Control: no-store`.

Authenticate Wrangler using your own Cloudflare account (`wrangler login`) or an externally supplied narrowly scoped API token. Do not put credentials in the source tree. Then deploy the verified staging folder:

```sh
bash Deployment/deploy.sh /tmp/idleminer-site-v1.8
```

Set `WRANGLER_BIN` if Wrangler is not on PATH. The existing **idle-miner** project uses legacy Pages. The script passes `--force` to retain direct Pages uploads; do not migrate it to Workers or add paid storage while running this command. After deployment, fetch the custom domain, guide, release notes, manifest and both installers; compare downloaded SHA-256 hashes with the release checksums. Verify HTTPS and the update manifest's no-store header before treating a release as public.

The apex custom domain must remain attached to this Pages project, with a proxied `CNAME` for `idleminer.app` pointing to `idle-miner.pages.dev`. Cloudflare manages TLS. GitHub Pages can be disabled after the custom domain and its downloads are verified; the source repository remains intact.
