# Idle Miner website and signed updates

The production site is [idleminer.app](https://idleminer.app/), served by the **idle-miner** Cloudflare Pages project. Deployments are direct uploads of static files. GitHub holds public source and issues. Release binaries, signing secrets, test fixtures, and staging output stay outside Git. Pages requires no R2 bucket, Worker, or paid add-on.

Use Node.js 20 or later and install the pinned Markdown renderer:

```sh
npm install --prefix Deployment
```

## Prepare and sign a release

Prepare the final audited release directory with these exact names for version 1.9: `Idle-Miner-1.9-macOS.dmg`, `Idle-Miner-1.9-Linux.tar.gz`, `Idle-Miner-1.9-source.tar.gz`, `Idle-Miner-How-To.md`, `LICENSE.txt`, and `SHA256SUMS.txt`. The checksum file must cover exactly the other five files with standard SHA-256 lines. Each asset must be nonempty and strictly smaller than Cloudflare Pages' 25 MiB per-file limit. Package, sign, and finish every archive before creating update feeds; changing an archive afterward invalidates the feed.

The Mac update framework and official tools are Sparkle **2.10.1** in `Vendor/Sparkle`. The update-signing private key lives only in the login Keychain under account `local.jeff.idleminer.updates`. Use Sparkle's official `generate_keys --account local.jeff.idleminer.updates` to initialize or inspect the account, and `-p` to print only its public key. Never use key export or put private keys in files, scripts, logs, source archives, or staging. Pin the matching public key in `macOS/Info.plist` (`SUPublicEDKey`) and `Linux/update_public_key.txt`. Mac requires signed appcasts with `SURequireSignedFeed` enabled. Apple Developer ID signing and notarization are separate checks and must be reported from the final artifact's actual verification results.

Write release notes to a separate UTF-8 **plain-text** file: 1–12000 characters, no HTML, angle brackets, or control characters other than tabs/newlines. Then create feeds in a new directory outside public source and release packages:

```sh
node Deployment/create-update-feeds.mjs \
  --version 1.9 --build 12 \
  --release-dir /path/to/Idle-Miner-1.9-release \
  --notes-file /path/to/1.9-update-notes.txt \
  --output /tmp/idleminer-feeds-1.9
```

The helper calls the official signer through argument arrays, using `--account local.jeff.idleminer.updates -p FILE`; it never retrieves the private key. It signs the actual Mac DMG and Linux archive, records their hashes, signatures and lengths, writes `stable.json` with schema 1 and the existing required fields plus `releaseNotesText` and each platform's `edSignature`/`length`, and signs its exact bytes into `stable.json.sig`. It creates `appcast.xml` with numeric build 12, short version 1.9, minimum macOS 14.0, plain-text inline notes, and the Mac enclosure's immutable URL, byte length, and signature. Sparkle signs the XML in place; the helper then verifies it with the official tool. Do not edit or reformat signed feeds. All signatures are additionally verified using the pinned public key.

Only fixture tests may use `--test-key-file /temporary/fixture-key --public-key-file /temporary/fixture-public`. The fixture key must be separately generated, outside the repository, and unrelated to the production Keychain key. Never publish fixture output.

## Build and verify the site

Keep old release URLs immutable. Supply the original audited 1.8 release directory so the deployment retains every original download byte:

```sh
node Deployment/build-site.mjs \
  --release-dir /path/to/Idle-Miner-1.9-release \
  --manifest /tmp/idleminer-feeds-1.9/stable.json \
  --previous-release-dir /path/to/Idle-Miner/Releases/Cloudflare-1.8 \
  --output /tmp/idleminer-site-v1.9
```

`--previous-release-dir` can be repeated for additional old releases. Each directory must contain one standard release set and valid checksums; the builder copies the original files unchanged. Version 1.9 staging requires 1.8 retention. The builder verifies JSON and appcast signatures before trusting version data, verifies both archive signatures/hashes/lengths, checks release-note version/build, and applies the Pages size limit to current and retained assets. It copies the exact signed feed bytes to `/updates/stable.json`, `/updates/stable.json.sig`, and `/updates/appcast.xml`. It copies only public site assets and rendered guides, never wallets, logs, credentials, Audit, or repository internals. All update endpoints use `Cache-Control: no-store`; download responses also use `no-store` so a request made before an artifact exists cannot leave an old website fallback cached at its future URL. The static `404.html` disables Pages SPA fallback; release URL bytes still remain immutable.

Run isolated fixture checks with:

```sh
npm test --prefix Deployment
node Deployment/verify-site.mjs /tmp/idleminer-site-v1.9
```

Fixtures create a fresh temporary signing key and test signed feed generation, byte preservation, immutable 1.8 retention, signature/hash rejection, invalid version/build, and notes limits. They do not access the production signing account or deploy.

## Authorized publication

Authenticate Wrangler with your own Cloudflare account (`wrangler login`) or an externally supplied narrowly scoped API token; never store credentials in source. After release approval, deploy the verified staging folder:

```sh
bash Deployment/deploy.sh /tmp/idleminer-site-v1.9
```

The deploy helper re-verifies the staged feeds and packages against the production pinned public key before invoking Wrangler. Set `WRANGLER_BIN` if Wrangler is not on PATH. The existing project uses legacy Pages; `--force` retains direct uploads. Do not migrate to Workers or add paid storage. After publication, fetch the custom domain, guides, release notes, both feeds, detached signature and installers; verify signatures and downloaded SHA-256 hashes, HTTPS, the no-store headers, and original 1.8 URLs. A local staged build does not establish live update behavior.

The apex domain must remain attached to this Pages project with a proxied `CNAME` for `idleminer.app` pointing to `idle-miner.pages.dev`. Cloudflare manages TLS. Existing 1.8 clients require one manual 1.9 installation; their old download links must continue working.
