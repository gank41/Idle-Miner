#!/usr/bin/env node
import { readFile, writeFile, mkdir, stat } from 'node:fs/promises';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { execFile } from 'node:child_process';
import { DEFAULT_ACCOUNT, inspectRelease, publicKey, validateVersion, validateNotes, verifySignature, verifyAppcast, externalOutput } from './update-feed-lib.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const options = {};
const allowed = new Set(['--version', '--build', '--release-dir', '--notes-file', '--output', '--account', '--public-key-file', '--test-key-file']);
for (let i = 2; i < process.argv.length; i += 2) {
  const flag = process.argv[i], value = process.argv[i + 1];
  if (!allowed.has(flag) || !value || options[flag]) throw new Error(`Invalid or duplicate option: ${flag}`);
  options[flag] = value;
}
for (const flag of ['--version', '--build', '--release-dir', '--notes-file', '--output']) if (!options[flag]) throw new Error('Usage: node create-update-feeds.mjs --version 1.9 --build 12 --release-dir PATH --notes-file PLAIN_TEXT --output NEW_DIRECTORY [--account ACCOUNT]');
const version = options['--version'], build = Number(options['--build']);
validateVersion(version, build);
if (String(build) !== options['--build']) throw new Error('Build must be an unsigned decimal integer.');
const releaseDir = resolve(options['--release-dir']);
const output = await externalOutput(options['--output'], [root, releaseDir]);
const keyPath = resolve(options['--public-key-file'] ?? join(root, 'Linux/update_public_key.txt'));
const key = publicKey(await readFile(keyPath, 'utf8'));
const notes = (await readFile(options['--notes-file'], 'utf8')).trim();
validateNotes(notes);
const records = await inspectRelease(releaseDir, version);
const account = options['--account'] ?? DEFAULT_ACCOUNT;
const signerArgs = options['--test-key-file'] ? ['--ed-key-file', resolve(options['--test-key-file'])] : ['--account', account];
if (options['--test-key-file'] && (resolve(options['--test-key-file']) === root || resolve(options['--test-key-file']).startsWith(root + '/'))) throw new Error('Fixture private keys must remain outside public source.');
if (options['--test-key-file'] && !options['--public-key-file']) throw new Error('Fixture signing requires an explicit separate public key.');
const signer = join(root, 'Vendor/Sparkle/bin/sign_update');
const run = promisify(execFile);
const sign = async path => (await run(signer, [...signerArgs, '-p', path], { maxBuffer: 1024 * 1024 })).stdout.trim();
const manifest = { schemaVersion: 1, version, build, releaseNotesURL: `https://idleminer.app/releases/v${version}.html`, releaseNotesText: notes, platforms: {} };
for (const [platform, suffix] of [['macos', 'macOS.dmg'], ['linux', 'Linux.tar.gz']]) {
  const name = `Idle-Miner-${version}-${suffix}`, record = records.get(name);
  const edSignature = await sign(join(releaseDir, name));
  verifySignature(record.bytes, edSignature, key, platform);
  manifest.platforms[platform] = { url: `https://idleminer.app/downloads/v${version}/${name}`, sha256: record.sha256, edSignature, length: record.length };
}
await mkdir(output, { recursive: false });
const manifestPath = join(output, 'stable.json');
const manifestBytes = Buffer.from(JSON.stringify(manifest, null, 2) + '\n');
await writeFile(manifestPath, manifestBytes);
const signature = await sign(manifestPath);
verifySignature(manifestBytes, signature, key, 'stable.json');
await writeFile(join(output, 'stable.json.sig'), signature + '\n');
const escape = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&apos;');
const mac = manifest.platforms.macos;
const appcastPath = join(output, 'appcast.xml');
const xml = `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
<title>Idle Miner updates</title><link>https://idleminer.app/</link><description>Idle Miner stable releases</description>
<item><title>Idle Miner ${escape(version)}</title><sparkle:version>${build}</sparkle:version><sparkle:shortVersionString>${escape(version)}</sparkle:shortVersionString><sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
<description sparkle:descriptionFormat="plain-text">${escape(notes)}</description>
<enclosure url="${escape(mac.url)}" length="${mac.length}" type="application/x-apple-diskimage" sparkle:edSignature="${mac.edSignature}" />
</item></channel></rss>\n`;
await writeFile(appcastPath, xml);
await sign(appcastPath); // Sparkle signs the actual XML bytes in place. Never rewrite after this call.
verifyAppcast(await readFile(appcastPath), key);
await run(signer, [...signerArgs, '--verify', appcastPath], { maxBuffer: 1024 * 1024 });
console.log(`Created authenticated feeds in ${output} for Idle Miner ${version} (build ${build}).`);
