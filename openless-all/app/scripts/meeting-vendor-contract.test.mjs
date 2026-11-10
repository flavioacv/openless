import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { relative } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../../', import.meta.url));
const vendor = new URL('../src-tauri/vendor/webrtc-aec3/', import.meta.url);
const manifest = readFileSync(new URL('Metadata/artifact-files.sha256', vendor), 'utf8');
const entries = manifest.trim().split(/\r?\n/);
assert.equal(entries.length, 3, 'ship the AEC binary, public header and XCFramework manifest');
for (const entry of entries) {
  const match = entry.match(/^([a-f0-9]{64})  (Artifacts\/[^\r\n]+)$/);
  assert.ok(match, `invalid AEC artifact manifest entry: ${entry}`);
  const [, digest, path] = match;
  assert.ok(!path.split('/').includes('..'));
  const file = fileURLToPath(new URL(path, vendor));
  assert.equal(createHash('sha256').update(readFileSync(file)).digest('hex'), digest, path);
  const ignored = spawnSync('git', ['check-ignore', '--no-index', '--quiet', '--', relative(root, file)], {
    cwd: root,
    encoding: 'utf8',
  });
  assert.ifError(ignored.error);
  assert.equal(ignored.status, 1, `${path} must be versionable for a clean CI checkout: ${ignored.stderr}`);
}
console.log('Meeting vendor: pinned AEC3 artifacts verified and not excluded by Git');
