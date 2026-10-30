import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { prepareRelease } from './prepare-fork-release.mjs';

const repo = fileURLToPath(new URL('..', import.meta.url));
const dir = mkdtempSync(join(tmpdir(), 'openless-release-'));
const files = ['package.json', 'package-lock.json', 'src-tauri/tauri.conf.json', 'src-tauri/Cargo.toml', 'src-tauri/Cargo.lock', 'src-tauri/src/android/updater_logic.rs'];
const app = join(dir, 'openless-all/app');
const fixtureBytes = Buffer.alloc(42, 1);
fixtureBytes.write('Ed');
const key = Buffer.from(`untrusted comment: test key\n${fixtureBytes.toString('base64')}\n`).toString('base64');
try {
  for (const name of files) {
    const target = join(app, name);
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, readFileSync(join(repo, 'openless-all/app', name)));
  }
  const original = files.map((name) => readFileSync(join(app, name), 'utf8'));
  for (const invalid of ['v2.0.3', '2.0', '02.0.3', '2.0.3-Beta.0', '2.0.3-Beta.01', '2.0.3;echo x', '2.0.3+build.1']) {
    assert.throws(() => prepareRelease(dir, invalid, key));
  }
  const officialBytes = Buffer.from(fixtureBytes);
  Buffer.from('3f324c5603a8ea1d', 'hex').copy(officialBytes, 2);
  const inherited = Buffer.from(`untrusted comment: official key\n${officialBytes.toString('base64')}\n`).toString('base64');
  assert.throws(() => prepareRelease(dir, '2.0.3', inherited), /herdada/);
  assert.throws(() => prepareRelease(dir, '2.0.3', 'garbage'), /chave pública/);
  assert.deepEqual(files.map((name) => readFileSync(join(app, name), 'utf8')), original);
  for (const version of ['2.0.3-Beta.1', '2.0.3']) {
    assert.equal(prepareRelease(dir, version, key), `v${version}-tauri`);
    assert.equal(prepareRelease(dir, version, key, true), `v${version}-tauri`);
    assert.throws(() => prepareRelease(dir, '3.0.0', key, true), /divergente/);
    const pkg = JSON.parse(readFileSync(join(app, 'package.json')));
    assert.deepEqual(pkg.dependencies, JSON.parse(original[0]).dependencies);
    const lock = JSON.parse(readFileSync(join(app, 'package-lock.json')));
    const before = JSON.parse(original[1]);
    delete lock.version;
    delete before.version;
    delete lock.packages[''].version;
    delete before.packages[''].version;
    assert.deepEqual(lock, before, 'all npm dependencies must remain unchanged');
    const cargoLock = readFileSync(join(app, 'src-tauri/Cargo.lock'), 'utf8');
    const normalize = (text) => text.replace(/(\[\[package\]\]\nname = "openless"\nversion = ")[^"]+/, '$1VERSION');
    assert.equal(normalize(cargoLock), normalize(original[4]));
  }
  writeFileSync(join(app, files[5]), 'invalid Rust fixture');
  const snapshot = files.map((name) => readFileSync(join(app, name), 'utf8'));
  assert.throws(() => prepareRelease(dir, '2.0.4', key), /Campo não encontrado/);
  assert.deepEqual(files.map((name) => readFileSync(join(app, name), 'utf8')), snapshot, 'validation failure must not partially write files');
  console.log('Fork release: Stable/Beta, invalid inputs, own keys, consistency and dependency preservation passed.');
} finally {
  rmSync(dir, { recursive: true, force: true });
}
