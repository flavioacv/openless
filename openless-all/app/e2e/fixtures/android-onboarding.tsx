import React, { useState } from 'react';
import { createRoot } from 'react-dom/client';
import '../../src/styles/tokens.css';
import '../../src/styles/global.css';
import '../../src/styles/refinements.css';

let mocks: typeof import('../../src/lib/ipc/mock-data');
const calls: string[] = [];
Object.assign(window, {
  androidGuideFixture: { calls },
  __TAURI_EVENT_PLUGIN_INTERNALS__: { unregisterListener() {} },
  __TAURI_INTERNALS__: {
    transformCallback: () => 1,
    invoke: async (command: string) => {
      calls.push(command);
      if (command === 'get_startup_snapshot')
        return { contractVersion: '2.0.0', backend: { running: true } };
      if (command === 'get_platform_capabilities')
        return { platform: 'android', supportsDesktopHotkey: false, supportsLocalAsr: false };
      if (command === 'check_microphone_permission') return 'granted';
      if (command === 'get_android_overlay_status')
        return { permission: 'granted', overlayVisible: true, message: '' };
      if (command === 'get_android_accessibility_status')
        return { state: 'enabled', enabled: true, operational: true, messageKey: '' };
      if (command === 'get_android_shizuku_status')
        return {
          state: 'notInstalled',
          messageKey: 'not_installed',
          accessibility: { registered: true, operational: true, messageKey: '' },
        };
      if (command === 'get_settings') return mocks.mockSettings;
      if (command === 'get_settings_snapshot')
        return { preferences: mocks.mockSettings, revision: 0 };
      if (command === 'get_hotkey_capability') return mocks.mockHotkeyCapability;
      // Keep the real provider step populated so advancing does not open an editor.
      if (command === 'list_channels')
        return [{
          id: 'groq',
          name: 'Groq',
          providerType: 'groq',
          enabled: true,
          order: 0,
          lastTest: null,
        }];
      if (command === 'list_provider_descriptors') return [];
      if (command === 'read_credential') return '';
      return null;
    },
  },
});
mocks = await import('../../src/lib/ipc/mock-data');
const [{ Onboarding }, { HotkeySettingsProvider }, { i18nReady }] = await Promise.all([
  import('../../src/components/Onboarding'),
  import('../../src/state/HotkeySettingsContext'),
  import('../../src/i18n'),
]);
await i18nReady;
const { default: i18n } = await import('../../src/i18n');
await i18n.changeLanguage('zh-CN');

function Fixture() {
  const [completed, setCompleted] = useState(false);
  return (
    <HotkeySettingsProvider>
      {/* The fork renders Onboarding directly; bound this fixture to the viewport
          without importing the upstream desktop layer, which the fork does not use. */}
      <div style={{ width: '100%', height: '100%', minWidth: 0, position: 'relative' }}>
        {completed ? (
          <h1>Guide completed</h1>
        ) : (
          <div className="ol-onboarding-layer" style={{ height: '100%' }}>
            <Onboarding onComplete={() => setCompleted(true)} />
          </div>
        )}
      </div>
    </HotkeySettingsProvider>
  );
}
createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <Fixture />
  </React.StrictMode>,
);
