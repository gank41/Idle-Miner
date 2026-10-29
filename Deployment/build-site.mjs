#!/usr/bin/env node
import { readFile, writeFile, mkdir, copyFile, readdir, stat } from 'node:fs/promises';
import { resolve, dirname, basename, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { inspectRelease, publicKey, validateManifest, verifySignature, verifyAppcastManifest, verifyArchives, externalOutput } from './update-feed-lib.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '..');
const { marked } = await import(process.env.IDLE_MINER_MARKED_MODULE ? pathToFileURL(process.env.IDLE_MINER_MARKED_MODULE).href : 'marked');
const options = {}, previousDirectories = [];
const allowed = new Set(['--release-dir', '--manifest', '--output', '--previous-release-dir', '--public-key-file']);
for (let i = 2; i < process.argv.length; i += 2) {
  const flag = process.argv[i], value = process.argv[i + 1];
  if (!allowed.has(flag) || !value) throw new Error(`Invalid option: ${flag}`);
  if (flag === '--previous-release-dir') previousDirectories.push(resolve(value));
  else { if (options[flag]) throw new Error(`Duplicate option: ${flag}`); options[flag] = value; }
}
if (!options['--release-dir'] || !options['--manifest'] || !options['--output']) {
  throw new Error('Usage: node build-site.mjs --release-dir PATH --manifest PATH --previous-release-dir PATH --output NEW_DIRECTORY');
}
const releaseDir = resolve(options['--release-dir']);
const output = await externalOutput(options['--output'], [root, releaseDir, ...previousDirectories]);
const manifestPath = resolve(options['--manifest']);
const manifestBytes = await readFile(manifestPath);
if (manifestBytes.length > 65536) throw new Error('Oversized release manifest.');
const key = publicKey(await readFile(resolve(options['--public-key-file'] ?? join(root, 'Linux/update_public_key.txt')), 'utf8'));
const manifestSignature = await readFile(manifestPath + '.sig', 'utf8');
verifySignature(manifestBytes, manifestSignature, key, 'stable.json');
const manifest = JSON.parse(manifestBytes.toString('utf8'));
validateManifest(manifest);
const version = manifest.version;
const releasePage = await readFile(join(root, 'docs/releases', `v${version}.md`), 'utf8');
if (!releasePage.includes(`(build ${manifest.build})`)) throw new Error('Release notes do not match the manifest build.');
const records = await inspectRelease(releaseDir, version);
verifyArchives(manifest, records, key);
const appcastBytes = await readFile(join(dirname(manifestPath), 'appcast.xml'));
if (appcastBytes.length > 65536) throw new Error('Oversized appcast.');
verifyAppcastManifest(appcastBytes, key, manifest);
const previousReleases = new Map();
for (const directory of previousDirectories) {
  const candidates = (await readdir(directory)).map(name => /^Idle-Miner-(\d+(?:\.\d+){1,2})-macOS\.dmg$/.exec(name)).filter(Boolean);
  if (candidates.length !== 1) throw new Error('Previous release directory must contain exactly one standard Mac release archive.');
  const oldVersion = candidates[0][1];
  if (oldVersion === version || previousReleases.has(oldVersion)) throw new Error('Duplicate current or previous release version.');
  const oldRecords = await inspectRelease(directory, oldVersion);
  previousReleases.set(oldVersion, { directory, records: oldRecords });
}
if (manifest.build > 11 && !previousReleases.has('1.8')) throw new Error('Keep immutable v1.8 download URLs: supply --previous-release-dir for the original audited 1.8 release.');
await mkdir(output, { recursive: false });
const copy = async (source, destination) => { await mkdir(dirname(destination), { recursive: true }); await copyFile(source, destination); };
for (const name of ['index.html', 'site.css', '_headers', '_redirects']) await copy(join(root, 'docs', name), join(output, name));
for (const name of await readdir(join(root, 'docs/assets'))) {
  if (/^[a-zA-Z0-9_.-]+\.(png|svg|webp|jpg|ico)$/.test(name)) await copy(join(root, 'docs/assets', name), join(output, 'assets', name));
}
const esc = value => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
const linkMap = new Map([
  ['HOWTO.md', '/guide.html'], ['PRIVACY.md', '/privacy.html'], ['BUILDING.md', '/building.html'],
  ['THIRD-PARTY-NOTICES.md', '/third-party-notices.html'], ['LICENSE', '/license.html'], ['README.md', '/'],
  ['Deployment/README.md', 'https://github.com/gank41/Idle-Miner/blob/main/Deployment/README.md']
]);
const renderer = new marked.Renderer();
renderer.heading = function ({ tokens, depth }) {
  const text = this.parser.parseInline(tokens);
  const id = text.replace(/<[^>]*>/g, '').toLowerCase().replace(/[^a-z0-9 -]/g, '').trim().replace(/\s+/g, '-');
  return `<h${depth} id="${id}">${text}</h${depth}>\n`;
};
marked.use({ renderer });
function frame(title, content, path) {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="theme-color" content="#0b172a"><title>${esc(title)} — Idle Miner</title><link rel="canonical" href="https://idleminer.app${path}"><link rel="icon" href="/assets/idle-miner.png"><link rel="stylesheet" href="/site.css"><style>.document{max-width:900px;padding:48px 24px 80px}.document h1{font-size:clamp(2rem,5vw,3rem);line-height:1.15;margin:0 0 1.2em}.document h2{font-size:1.5rem;margin:2em 0 .65em}.document p,.document ul,.document ol,.document table,.document pre{margin:1em 0}.document li{margin:.45em 0}.document a{text-decoration:underline;color:#9ecaff}.document table{display:block;overflow-x:auto;border-collapse:collapse}.document th,.document td{padding:.7em;border:1px solid #62718b;vertical-align:top}.document pre{overflow:auto;padding:1em;background:#14243b;white-space:pre-wrap}.document code{overflow-wrap:anywhere;white-space:normal}.document pre code{white-space:pre-wrap}.document nav{margin-bottom:2.5em;display:flex;gap:1.5em;flex-wrap:wrap}</style></head><body><main class="document wrap"><nav aria-label="Page navigation"><a href="/">Idle Miner</a><a href="/guide.html">Guide</a><a href="/#downloads">Downloads</a><a href="/releases/">Release notes</a><a href="https://github.com/gank41/Idle-Miner">Source</a></nav>${content}</main></body></html>\n`;
}
function rewriteLinks(html) {
  return html.replace(/href="([^"]+)"/g, (full, href) => {
    const [target, fragment] = href.split('#');
    const normalized = target.replace(/^https:\/\/github.com\/gank41\/Idle-Miner\/blob\/main\//, '').replace(/^\.\.\//, '');
    let to = linkMap.get(normalized);
    if (!to && /^(docs\/)?releases\/v[\d.]+\.md$/.test(normalized)) to = '/releases/' + basename(normalized, '.md') + '.html';
    if (!to && /^v[\d.]+\.md$/.test(normalized)) to = '/releases/' + basename(normalized, '.md') + '.html';
    return to ? `href="${to}${fragment ? '#' + fragment : ''}"` : full;
  });
}
for (const [source, destination, title] of [
  ['HOWTO.md', 'guide.html', 'Install and use Idle Miner'], ['PRIVACY.md', 'privacy.html', 'Privacy'],
  ['BUILDING.md', 'building.html', 'Building Idle Miner'], ['THIRD-PARTY-NOTICES.md', 'third-party-notices.html', 'Third-party notices']
]) {
  const content = rewriteLinks(marked.parse(await readFile(join(root, source), 'utf8')));
  await writeFile(join(output, destination), frame(title, content, '/' + destination));
}
await writeFile(join(output, 'license.html'), frame('GNU General Public License', '<h1>GNU General Public License</h1><pre>' + esc(await readFile(join(root, 'LICENSE'), 'utf8')) + '</pre>', '/license.html'));
await mkdir(join(output, 'releases'));
const releaseFiles = (await readdir(join(root, 'docs/releases'))).filter(name => /^v[\d.]+\.md$/.test(name)).sort((a,b) => b.localeCompare(a, undefined, { numeric: true }));
for (const file of releaseFiles) {
  const content = await readFile(join(root, 'docs/releases', file), 'utf8');
  const htmlName = file.replace(/\.md$/, '.html');
  await writeFile(join(output, 'releases', htmlName), frame('Release ' + basename(file, '.md'), rewriteLinks(marked.parse(content)), '/releases/' + htmlName));
}
await writeFile(join(output, 'releases/index.html'), frame('Release notes', '<h1>Release notes</h1><ul>' + releaseFiles.map(file => `<li><a href="/releases/${file.replace(/\.md$/, '.html')}">${esc(basename(file, '.md'))}</a></li>`).join('') + `</ul><p><a href="/downloads/v${version}/SHA256SUMS.txt">Current release SHA-256 checksums</a></p>`, '/releases/'));
for (const name of records.keys()) await copy(join(releaseDir, name), join(output, 'downloads', 'v' + version, name));
for (const [oldVersion, { directory, records: oldRecords }] of previousReleases) {
  for (const name of oldRecords.keys()) await copy(join(directory, name), join(output, 'downloads', 'v' + oldVersion, name));
}
await mkdir(join(output, 'updates'));
await writeFile(join(output, 'updates/stable.json'), manifestBytes);
await writeFile(join(output, 'updates/stable.json.sig'), manifestSignature);
await writeFile(join(output, 'updates/appcast.xml'), appcastBytes);
console.log(`Built ${output}: Idle Miner ${version} (build ${manifest.build}), authenticated feeds and archives, installer URLs, hashes, immutable previous downloads, checksum coverage and Pages file sizes.`);
