import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export function prepareRelease(root, version, publicKey, check = false) {
  const numeric = '(?:0|[1-9][0-9]*)';
  if (!new RegExp(`^${numeric}\\.${numeric}\\.${numeric}(?:-Beta\\.[1-9][0-9]*)?$`).test(version)) {
    throw new Error('Use X.Y.Z ou X.Y.Z-Beta.N, sem prefixo v nem metadados.');
  }
  const decoded = Buffer.from(publicKey ?? '', 'base64').toString('utf8').trim().split(/\r?\n/);
  const keyBytes = Buffer.from(decoded[1] ?? '', 'base64');
  if (decoded.length !== 2 || !decoded[0].startsWith('untrusted comment:') || keyBytes.length !== 42 || !['Ed', 'ED'].includes(keyBytes.subarray(0, 2).toString())) {
    throw new Error('Configure OPENLESS_UPDATER_PUBLIC_KEY com a chave pública Base64 gerada pelo Tauri.');
  }
  const app = resolve(root, 'openless-all/app');
  const read = (name) => readFileSync(resolve(app, name), 'utf8');
  const officialKeyId = '3f324c5603a8ea1d';
  if (keyBytes.subarray(2, 10).toString('hex') === officialKeyId) {
    throw new Error('A chave herdada do oficial não pode assinar releases do fork. Gere um par próprio.');
  }
  const outputs = new Map();
  for (const name of ['package.json', 'package-lock.json', 'src-tauri/tauri.conf.json']) {
    const data = JSON.parse(read(name));
    if (check && data.version !== version) throw new Error(`Versão divergente em ${name}`);
    data.version = version;
    if (name === 'package-lock.json') {
      if (check && data.packages[''].version !== version) throw new Error('Versão divergente no lock npm');
      data.packages[''].version = version;
    }
    if (name.endsWith('tauri.conf.json')) {
      if (check && data.plugins.updater.pubkey !== publicKey) throw new Error('Chave pública desktop divergente');
      data.plugins.updater.pubkey = publicKey;
      for (const endpoint of data.plugins.updater.endpoints) {
        if (!endpoint.includes('/flavioacv/openless/releases/')) throw new Error('Endpoint externo ao fork');
      }
    }
    outputs.set(name, `${JSON.stringify(data, null, 2)}\n`);
  }
  for (const [name, pattern] of [
    ['src-tauri/Cargo.toml', /(\[package\][\s\S]*?\nversion = ")([^"]+)(")/],
    ['src-tauri/Cargo.lock', /(\[\[package\]\]\nname = "openless"\nversion = ")([^"]+)(")/],
    ['src-tauri/src/android/updater_logic.rs', /(pub const UPDATER_PUBKEY_B64: &str\s*=\s*")([^"]+)(")/],
  ]) {
    const source = read(name);
    const match = source.match(pattern);
    if (!match) throw new Error(`Campo não encontrado: ${name}`);
    const value = name.endsWith('.rs') ? publicKey : version;
    if (check && match[2] !== value) throw new Error(`Valor divergente: ${name}`);
    outputs.set(name, source.replace(pattern, (_, before, old, after) => before + value + after));
  }
  // Validate every file before writing; preserve all dependencies and lock entries.
  if (!check) for (const [name, content] of outputs) writeFileSync(resolve(app, name), content);
  return `v${version}-tauri`;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = fileURLToPath(new URL('..', import.meta.url));
  const tag = prepareRelease(root, process.argv[2], process.env.OPENLESS_UPDATER_PUBLIC_KEY, process.argv.includes('--check'));
  console.log(tag);
}
