#!/usr/bin/env node
import { readFile, writeFile, mkdir, copyFile, readdir, stat } from 'node:fs/promises';
import { resolve, dirname, basename, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '..');
const { marked } = await import(process.env.IDLE_MINER_MARKED_MODULE ? pathToFileURL(process.env.IDLE_MINER_MARKED_MODULE).href : 'marked');
const options = {};
for (let i = 2; i < process.argv.length; i += 2) options[process.argv[i]] = process.argv[i + 1];
if (!options['--release-dir'] || !options['--manifest'] || !options['--output']) {
  throw new Error('Usage: node build-site.mjs --release-dir PATH --manifest PATH --output NEW_DIRECTORY');
}
const releaseDir = resolve(options['--release-dir']);
const output = resolve(options['--output']);
if (output === root || output.startsWith(root + '/') || output === releaseDir) throw new Error('Use a new staging directory outside the source and release folders.');
try { await stat(output); throw new Error('Staging directory already exists; choose a new empty destination.'); }
catch (error) { if (error.code !== 'ENOENT') throw error; }
const manifest = JSON.parse(await readFile(options['--manifest'], 'utf8'));
if (manifest.schemaVersion !== 1 || !/^\d+(\.\d+){1,2}$/.test(manifest.version) || !Number.isSafeInteger(manifest.build) || manifest.build < 1) throw new Error('Invalid release manifest.');
const version = manifest.version;
if (manifest.releaseNotesURL !== `https://idleminer.app/releases/v${version}.html`) throw new Error('Unexpected release notes URL.');
const releasePage = await readFile(join(root, 'docs/releases', `v${version}.md`), 'utf8');
if (!releasePage.includes(`(build ${manifest.build})`)) throw new Error('Release notes do not match the manifest build.');
const files = [
  `Idle-Miner-${version}-macOS.dmg`, `Idle-Miner-${version}-Linux.tar.gz`,
  `Idle-Miner-${version}-source.tar.gz`, 'SHA256SUMS.txt', 'LICENSE.txt', 'Idle-Miner-How-To.md'
];
for (const file of files) {
  const size = (await stat(join(releaseDir, file))).size;
  if (!size || size >= 25 * 1024 * 1024) throw new Error(`Missing, empty or oversized Pages asset: ${file}`);
}
for (const [platform, suffix] of [['macos', 'macOS.dmg'], ['linux', 'Linux.tar.gz']]) {
  const name = `Idle-Miner-${version}-${suffix}`;
  const entry = manifest.platforms?.[platform];
  const checksum = createHash('sha256').update(await readFile(join(releaseDir, name))).digest('hex');
  if (entry?.url !== `https://idleminer.app/downloads/v${version}/${name}` || entry?.sha256 !== checksum) throw new Error(`Invalid ${platform} download URL or checksum.`);
}
const sums = await readFile(join(releaseDir, 'SHA256SUMS.txt'), 'utf8');
for (const file of files.filter(name => name !== 'SHA256SUMS.txt')) {
  const digest = createHash('sha256').update(await readFile(join(releaseDir, file))).digest('hex');
  if (!sums.split('\n').some(line => line.startsWith(digest) && line.trimEnd().endsWith(file))) throw new Error(`Checksum file does not cover ${file}.`);
}
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
for (const name of files) await copy(join(releaseDir, name), join(output, 'downloads', 'v' + version, name));
await mkdir(join(output, 'updates'));
await writeFile(join(output, 'updates/stable.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log(`Built ${output}: Idle Miner ${version} (build ${manifest.build}), verified installer URLs, hashes, release checksum coverage and Pages file sizes.`);
