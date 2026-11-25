import { createInstance } from 'i18next';
import { pt } from './pt';
import { zhCN } from './zh-CN';
import i18n, { i18nReady } from './index';
import { formatComboParts, getHotkeyCodeLabel, MODIFIER_CHORD_PRIMARY } from '../lib/hotkey';

const assert = {
  ok(value: unknown, message: string) {
    if (!value) throw new Error(message);
  },
  equal(actual: unknown, expected: unknown) {
    if (actual !== expected) throw new Error(`Expected ${String(expected)}, got ${String(actual)}`);
  },
  notEqual(actual: unknown, expected: unknown) {
    if (actual === expected) throw new Error(`Untranslated key: ${String(actual)}`);
  },
  deepEqual(actual: unknown, expected: unknown, message = 'Values differ') {
    if (JSON.stringify(actual) !== JSON.stringify(expected)) throw new Error(message);
  },
  doesNotMatch(value: string, expression: RegExp, message: string) {
    if (expression.test(value)) throw new Error(message);
  },
};

function flatten(value: unknown, prefix = ''): Record<string, string> {
  if (typeof value === 'string') return { [prefix]: value };
  return Object.fromEntries(
    Object.entries(value as Record<string, unknown>).flatMap(([key, child]) =>
      Object.entries(flatten(child, prefix ? `${prefix}.${key}` : key)),
    ),
  );
}

const translated = flatten(pt);
for (const [key, source] of Object.entries(flatten(zhCN))) {
  assert.ok(translated[key]?.trim(), `Portuguese translation missing: ${key}`);
  assert.doesNotMatch(translated[key], /\p{Script=Han}/u, `Chinese UI copy in ${key}`);
  const placeholders = (text: string) =>
    [...text.matchAll(/\{\{([^}]+)\}\}/g)].map((m) => m[1]).sort();
  assert.deepEqual(
    placeholders(translated[key]),
    placeholders(source),
    `Interpolation mismatch: ${key}`,
  );
}

const locale = createInstance();
await locale.init({ lng: 'pt', fallbackLng: false, resources: { pt: { translation: pt } } });
for (const key of [
  'common.cancelled',
  'common.networkError',
  'marketplace.oauth.expiredError',
  'hotkey.unset',
  'hotkey.modeDoubleClickSuffix',
  'hotkey.usageDoubleClick',
]) {
  assert.notEqual(locale.t(key), key);
}

await i18nReady;
i18n.addResourceBundle('pt', 'translation', pt);
await i18n.changeLanguage('pt');
assert.equal(getHotkeyCodeLabel('ControlRight'), 'Direita Ctrl');
assert.equal(getHotkeyCodeLabel('Space'), 'Espaço');
Object.defineProperty(globalThis, 'navigator', {
  configurable: true,
  value: { platform: 'Win32', userAgent: 'Windows' },
});
assert.deepEqual(
  formatComboParts({ primary: MODIFIER_CHORD_PRIMARY, modifiers: ['ctrl-left', 'cmd-right'] }),
  ['Direita Win', 'Esquerda Ctrl'],
);
console.log('Portuguese catalog, interpolation and physical shortcut labels passed');
