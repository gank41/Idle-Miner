#!/usr/bin/env node
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm, truncate } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash, createPrivateKey, createPublicKey, randomBytes } from 'node:crypto';
import { promisify } from 'node:util';
import { execFile } from 'node:child_process';
import { releaseFiles, publicKey, verifySignature, verifyAppcast, verifyArchives, inspectRelease, validateNotes, validateVersion } from './update-feed-lib.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const fixture = await mkdtemp(join(tmpdir(), 'idleminer-feed-tests-'));
const run = promisify(execFile);
const execute = (name, args) => run(process.execPath, [join(root, 'Deployment', name), ...args], { maxBuffer: 1024 * 1024 });
let count = 0;
try {
  const seed = randomBytes(32);
  const privateKey = createPrivateKey({ key: Buffer.concat([Buffer.from('302e020100300506032b657004220420', 'hex'), seed]), format: 'der', type: 'pkcs8' });
  const rawPublic = createPublicKey(privateKey).export({ format: 'der', type: 'spki' }).subarray(-32).toString('base64');
  const seedPath = join(fixture, 'fixture-key'), keyPath = join(fixture, 'fixture-public');
  await writeFile(seedPath, seed.toString('base64'), { mode: 0o600 });
  await writeFile(keyPath, rawPublic + '\n');
  const key = publicKey(rawPublic);
  async function release(version) {
    const directory = join(fixture, 'release-' + version);
    await mkdir(directory);
    const sums = [];
    for (const name of releaseFiles(version).filter(name => name !== 'SHA256SUMS.txt')) {
      const bytes = Buffer.from(`TEST FIXTURE ONLY ${name}\n`);
      await writeFile(join(directory, name), bytes);
      sums.push(createHash('sha256').update(bytes).digest('hex') + '  ' + name);
    }
    await writeFile(join(directory, 'SHA256SUMS.txt'), sums.join('\n') + '\n');
    return directory;
  }
  const current = await release('1.9'), previous = await release('1.8');
  const feeds = join(fixture, 'feeds'), notes = join(fixture, 'notes.txt');
  await writeFile(notes, 'Built-in updates.\nWallets remain unchanged: "public" & private.\n');
  const signerArgs = ['--version', '1.9', '--build', '12', '--release-dir', current, '--notes-file', notes, '--output', feeds, '--public-key-file', keyPath, '--test-key-file', seedPath];
  await execute('create-update-feeds.mjs', signerArgs);
  const manifestPath = join(feeds, 'stable.json');
  const manifestBytes = await readFile(manifestPath), signature = await readFile(manifestPath + '.sig', 'utf8');
  verifySignature(manifestBytes, signature, key, 'fixture manifest');
  const appcastPath = join(feeds, 'appcast.xml'), appcastBytes = await readFile(appcastPath);
  verifyAppcast(appcastBytes, key);
  count++;
  const manifest = JSON.parse(manifestBytes);
  const records = await inspectRelease(current, '1.9');
  const badManifest = structuredClone(manifest);
  badManifest.platforms.linux.edSignature = Buffer.alloc(64).toString('base64');
  assert.throws(() => verifyArchives(badManifest, records, key), /Invalid Ed25519/);
  badManifest.platforms.linux.edSignature = manifest.platforms.linux.edSignature;
  badManifest.platforms.linux.length++;
  assert.throws(() => verifyArchives(badManifest, records, key), /length/);
  assert.throws(() => validateNotes('x'.repeat(12001)), /bounded/);
  assert.throws(() => validateVersion(1.9, 12), /version/);
  count += 4;
  const baseArgs = ['--release-dir', current, '--manifest', manifestPath, '--public-key-file', keyPath, '--previous-release-dir', previous];
  const output = join(fixture, 'site');
  await execute('build-site.mjs', [...baseArgs, '--output', output]);
  assert.match(await readFile(join(output, '_headers'), 'utf8'), /\/downloads\/\*\n  Cache-Control: no-store/, 'Missing download URLs must not acquire year-long cached website fallbacks');
  await assert.doesNotReject(() => readFile(join(output, '404.html')), 'A real static 404 must disable Pages SPA fallback for missing artifacts');
  count += 2;
  assert.deepEqual(await readFile(join(output, 'updates/stable.json')), manifestBytes);
  assert.deepEqual(await readFile(join(output, 'updates/appcast.xml')), appcastBytes);
  for (const name of releaseFiles('1.8')) assert.deepEqual(await readFile(join(output, 'downloads/v1.8', name)), await readFile(join(previous, name)));
  count++;
  async function rejects(label, change, restore, args = baseArgs) {
    if (change) await change();
    await assert.rejects(execute('build-site.mjs', [...args, '--output', join(fixture, 'reject-' + label)]));
    if (restore) await restore();
    count++;
  }
  await rejects('manifest-signature', () => writeFile(manifestPath + '.sig', Buffer.alloc(64).toString('base64')), () => writeFile(manifestPath + '.sig', signature));
  await rejects('manifest-bytes', () => writeFile(manifestPath, Buffer.concat([manifestBytes, Buffer.from(' ')])), () => writeFile(manifestPath, manifestBytes));
  await rejects('appcast-signature', () => writeFile(appcastPath, appcastBytes.toString().replace('Idle Miner updates', 'Idle Miner tampered')), () => writeFile(appcastPath, appcastBytes));
  const mac = join(current, 'Idle-Miner-1.9-macOS.dmg'), macBytes = await readFile(mac);
  await rejects('archive-hash', () => writeFile(mac, 'tampered archive'), () => writeFile(mac, macBytes));
  await rejects('oversized-archive', () => truncate(mac, 25 * 1024 * 1024), () => writeFile(mac, macBytes));
  const old = join(previous, 'Idle-Miner-1.8-Linux.tar.gz'), oldBytes = await readFile(old);
  await rejects('previous-hash', () => writeFile(old, 'tampered immutable archive'), () => writeFile(old, oldBytes));
  await rejects('missing-previous', undefined, undefined, baseArgs.slice(0, -2));
  await assert.rejects(execute('create-update-feeds.mjs', signerArgs.map(value => value === '12' ? '0' : value)));
  count++;
  await writeFile(notes, '<script>no markup</script>');
  await assert.rejects(execute('create-update-feeds.mjs', signerArgs.map(value => value === feeds ? join(fixture, 'bad-notes') : value)));
  count++;
  console.log(`Passed ${count} signed-feed/staging fixture checks; all fixtures stayed in ${fixture}.`);
} finally { await rm(fixture, { recursive: true, force: true }); }
