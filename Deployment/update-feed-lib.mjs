import { readFile, stat, realpath, lstat } from 'node:fs/promises';
import { createHash, createPublicKey, verify } from 'node:crypto';
import { join, dirname, basename, resolve } from 'node:path';

export const MAX_ASSET_BYTES = 25 * 1024 * 1024;
export const MAX_NOTES_LENGTH = 12000;
export const DEFAULT_ACCOUNT = 'local.jeff.idleminer.updates';
export function releaseFiles(version) {
  return [`Idle-Miner-${version}-macOS.dmg`, `Idle-Miner-${version}-Linux.tar.gz`,
    `Idle-Miner-${version}-source.tar.gz`, 'SHA256SUMS.txt', 'LICENSE.txt', 'Idle-Miner-How-To.md'];
}
export function validateVersion(version, build) {
  if (typeof version !== 'string' || !/^\d+(\.\d+){1,2}$/.test(version) || !Number.isSafeInteger(build) || build < 1) throw new Error('Invalid release version or build.');
}
export function validateNotes(notes) {
  if (typeof notes !== 'string' || !notes.trim() || notes.length > MAX_NOTES_LENGTH || /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f<>]/.test(notes)) throw new Error('Release notes must be bounded plain text (1–12000 characters, no markup/control characters).');
}
export function publicKey(raw) {
  const text = raw.trim();
  const data = Buffer.from(text, 'base64');
  if (data.length !== 32 || data.toString('base64') !== text) throw new Error('Invalid pinned Ed25519 public key.');
  return createPublicKey({ key: Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'), data]), format: 'der', type: 'spki' });
}
export function verifySignature(bytes, signature, key, label) {
  const text = signature.trim();
  const data = Buffer.from(text, 'base64');
  if (data.length !== 64 || data.toString('base64') !== text || !verify(null, bytes, key, data)) throw new Error(`Invalid Ed25519 signature: ${label}`);
}
export function verifyAppcast(bytes, key) {
  const marker = Buffer.from('<!-- sparkle-signatures:');
  const offset = bytes.lastIndexOf(marker);
  if (offset < 1) throw new Error('Unsigned appcast.');
  const match = /^<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+/=]+)\nlength: ([0-9]+)\n-->\n?$/.exec(bytes.subarray(offset).toString('utf8'));
  if (!match || Number(match[2]) !== offset) throw new Error('Invalid Sparkle appcast signature boundary.');
  verifySignature(bytes.subarray(0, offset), match[1], key, 'appcast');
  return bytes.subarray(0, offset).toString('utf8');
}
export async function inspectRelease(directory, version) {
  validateVersion(version, 1);
  const records = new Map();
  for (const name of releaseFiles(version)) {
    const path = join(directory, name);
    const info = await stat(path);
    if (!info.isFile() || !info.size || info.size >= MAX_ASSET_BYTES) throw new Error(`Missing, empty or oversized Pages asset: ${name}`);
    const bytes = await readFile(path);
    records.set(name, { bytes, length: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex') });
  }
  const sums = records.get('SHA256SUMS.txt').bytes.toString('utf8');
  const entries = new Map();
  for (const line of sums.split('\n').filter(Boolean)) {
    const match = /^([a-f0-9]{64}) [ *]([^/\\]+)$/.exec(line);
    if (!match || entries.has(match[2])) throw new Error('Invalid or duplicate SHA256SUMS entry.');
    entries.set(match[2], match[1]);
  }
  for (const [name, record] of records) {
    if (name !== 'SHA256SUMS.txt' && entries.get(name) !== record.sha256) throw new Error(`Checksum file does not cover ${name}.`);
  }
  if (entries.size !== records.size - 1) throw new Error('Unexpected assets in SHA256SUMS.');
  return records;
}
export function validateManifest(manifest) {
  validateVersion(manifest.version, manifest.build);
  if (manifest.schemaVersion !== 1 || manifest.releaseNotesURL !== `https://idleminer.app/releases/v${manifest.version}.html`) throw new Error('Invalid release manifest.');
  validateNotes(manifest.releaseNotesText);
}
export function verifyArchives(manifest, records, key) {
  for (const [platform, suffix] of [['macos', 'macOS.dmg'], ['linux', 'Linux.tar.gz']]) {
    const name = `Idle-Miner-${manifest.version}-${suffix}`;
    const entry = manifest.platforms?.[platform];
    const record = records.get(name);
    if (entry?.url !== `https://idleminer.app/downloads/v${manifest.version}/${name}` || entry.sha256 !== record.sha256 || entry.length !== record.length) throw new Error(`Invalid ${platform} URL, checksum or length.`);
    verifySignature(record.bytes, entry.edSignature ?? '', key, platform);
  }
}

export function verifyAppcastManifest(bytes, key, manifest) {
  const xml = verifyAppcast(bytes, key);
  const mac = manifest.platforms.macos;
  const esc = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
  const decode = value => value.replace(/&(amp|lt|gt|quot|apos);/g, (_, entity) => ({ amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" }[entity]));
  for (const expected of [
    `<sparkle:version>${manifest.build}</sparkle:version>`,
    `<sparkle:shortVersionString>${manifest.version}</sparkle:shortVersionString>`,
    '<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>',
    `<enclosure url="${esc(mac.url)}" length="${mac.length}" type="application/x-apple-diskimage" sparkle:edSignature="${mac.edSignature}"></enclosure>`
  ]) if (!xml.includes(expected)) throw new Error('Appcast does not match authenticated release manifest.');
  const descriptions = [...xml.matchAll(/<description sparkle:descriptionFormat="plain-text">([^<]*)<\/description>/g)];
  if (descriptions.length !== 1 || decode(descriptions[0][1]) !== manifest.releaseNotesText) throw new Error('Appcast release notes do not match authenticated manifest.');
  if ((xml.match(/<item>/g) ?? []).length !== 1 || (xml.match(/<enclosure /g) ?? []).length !== 1) throw new Error('Unexpected appcast items.');
}

export async function externalOutput(path, excludedDirectories) {
  const output = join(await realpath(dirname(resolve(path))), basename(path));
  for (const excluded of excludedDirectories) {
    const canonical = await realpath(excluded);
    if (output === canonical || output.startsWith(canonical + '/') || canonical.startsWith(output + '/')) throw new Error('Output must be outside source and release directories.');
  }
  try { await lstat(output); throw new Error('Output already exists; choose a new directory.'); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  return output;
}
