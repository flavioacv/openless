import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const read = (path) => readFileSync(new URL(path, import.meta.url), 'utf8');
const config = JSON.parse(read('../src-tauri/tauri.conf.json'));
for (const endpoint of config.plugins.updater.endpoints) {
  assert.ok(endpoint.includes('/flavioacv/openless/releases/'), endpoint);
}
for (const path of [
  '../src-tauri/src/commands/settings.rs',
  '../src-tauri/src/android/updater_logic.rs',
  '../src/components/AutoUpdate.tsx',
  '../src/pages/settings/AboutSection.tsx',
  '../src/components/SettingsModal.tsx',
]) {
  assert.ok(!read(path).includes('Open-Less/openless'), path);
}
assert.match(read('../../../.github/workflows/android-apk.yml'), /OPENLESS_UPDATE_REPO: \$\{\{ github.repository \}\}/);

const dir = mkdtempSync(join(tmpdir(), 'openless-updater-'));
try {
  writeFileSync(join(dir, 'OpenLess_test_arm64-v8a.apk'), 'test artifact');
  writeFileSync(join(dir, 'OpenLess_test_arm64-v8a.apk.sig'), 'test signature');
  for (const channel of ['stable', 'beta']) {
    const env = { ...process.env, OPENLESS_UPDATE_TARGET: 'android', OPENLESS_UPDATE_ARCH: 'aarch64', OPENLESS_UPDATE_APK_DIR: dir, OPENLESS_RELEASE_CHANNEL: channel, OPENLESS_RELEASE_TAG: 'v2.0.2-Beta.2-tauri' };
    delete env.OPENLESS_UPDATE_REPO;
    execFileSync(process.execPath, [fileURLToPath(new URL('./write-updater-manifest.mjs', import.meta.url))], { env });
    const suffix = channel === 'beta' ? '-beta' : '';
    const manifest = JSON.parse(readFileSync(join(dir, `latest-android-aarch64${suffix}.json`), 'utf8'));
    assert.ok(manifest.url.startsWith('https://github.com/flavioacv/openless/releases/'));
    assert.ok(manifest.url.includes(channel === 'beta' ? '/download/v2.0.2-Beta.2-tauri/' : '/latest/download/'));
    assert.equal(manifest.signature, 'test signature');
    const mirror = JSON.parse(readFileSync(join(dir, `latest-android-aarch64${suffix}-mirror.json`), 'utf8'));
    assert.ok(mirror.url.includes('/flavioacv/openless/releases/'));
  }
} finally {
  rmSync(dir, { recursive: true, force: true });
}
console.log('Fork updater: endpoints, links, workflow and Stable/Beta manifests passed.');
