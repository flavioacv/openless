"""Exercise native menu translations and the resources shipped to the installer."""
from pathlib import Path
import json
import plistlib
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class NativeLocalizationTests(unittest.TestCase):
    def test_actual_rust_menu_labels_and_locale_aliases(self):
        host = (ROOT / 'src-tauri/src/lib.rs').read_text()
        native = (ROOT / 'src-tauri/src/native_capsule.rs').read_text()
        structure = host.split('struct TrayLabels {', 1)[1].split('\n}', 1)[0]
        method = host.split('    fn for_locale(locale:', 1)[1].split('    fn style_pack_name', 1)[0]
        normalize = native.split('pub(crate) fn normalize_ui_locale', 1)[1].split('/// Use the persisted', 1)[0]
        source = ('mod native_capsule { pub fn normalize_ui_locale' + normalize + '}\n'
                  + '#[allow(dead_code)] struct TrayLabels {' + structure + '\n}\n'
                  + 'impl TrayLabels { fn for_locale(locale:' + method + '}\n'
                  + '''
#[test] fn portuguese_menu_is_complete() {
    for locale in ["pt", "pt-BR", "pt_PT.UTF-8", "PT_br"] {
        let labels = TrayLabels::for_locale(locale);
        assert_eq!(labels.toggle, "Mostrar janela principal");
        assert_eq!(labels.style, "Estilo de saída");
        assert_eq!(labels.microphone, "Selecionar microfone");
        assert_eq!(labels.default_microphone, "Microfone padrão do sistema");
        assert_eq!(labels.no_microphones, "Nenhum microfone encontrado");
        assert_eq!(labels.default_device_suffix, " (Padrão do sistema)");
        assert_eq!(labels.quit, "Sair do OpenLess");
        assert_eq!(labels.raw, "Texto original");
        assert_eq!(labels.light, "Aprimoramento leve");
        assert_eq!(labels.structured, "Estruturado");
        assert_eq!(labels.formal, "Formal");
    }
}
#[test] fn other_locales_and_fallback_remain_available() {
    assert_eq!(TrayLabels::for_locale("zh-CN").toggle, "显示主窗口");
    assert_eq!(TrayLabels::for_locale("zh_Hant_HK").toggle, "顯示主視窗");
    assert_eq!(TrayLabels::for_locale("fr-CA").quit, "Quitter OpenLess");
    assert_eq!(TrayLabels::for_locale("unknown").quit, "Quit OpenLess");
}
''')
        with tempfile.TemporaryDirectory(prefix='openless-native-locale-') as directory:
            directory = Path(directory)
            fixture = directory / 'menu.rs'
            fixture.write_text(source)
            binary = directory / 'menu-test'
            subprocess.run(['rustc', '--edition=2021', '--test', str(fixture), '-o', str(binary)], check=True)
            subprocess.run([str(binary)], check=True)

    def test_permission_translations_are_bundled_and_parseable(self):
        config = json.loads((ROOT / 'src-tauri/tauri.conf.json').read_text())
        base = plistlib.loads((ROOT / 'src-tauri/Info.plist').read_bytes())
        keys = {key for key in base if key.endswith('UsageDescription')}
        self.assertEqual(len(keys), 4)
        for locale in ['pt', 'pt-BR', 'en', 'zh-Hans', 'zh-Hant']:
            self.assertIn(locale, base['CFBundleLocalizations'])
            source = f'locales/{locale}.lproj/InfoPlist.strings'
            self.assertEqual(config['bundle']['resources'][source], f'{locale}.lproj/InfoPlist.strings')
            file = ROOT / 'src-tauri' / source
            subprocess.run(['plutil', '-lint', str(file)], check=True, stdout=subprocess.PIPE)
            text = file.read_text()
            actual = dict(re.findall(r'"([^"\n]+)"\s*=\s*"([^"\n]+)";', text))
            self.assertEqual(set(actual), keys)
            self.assertTrue(all(value.strip() for value in actual.values()))
            if locale.startswith('pt'):
                self.assertIn('microfone', actual['NSMicrophoneUsageDescription'])
                self.assertFalse(re.search('[\u4e00-\u9fff]', text))
        self.assertFalse(re.search('[\u4e00-\u9fff]', '\n'.join(base[key] for key in keys)))

    def test_windows_installers_offer_brazilian_portuguese(self):
        windows = json.loads((ROOT / 'src-tauri/tauri.conf.json').read_text())['bundle']['windows']
        self.assertIn('PortugueseBR', windows['nsis']['languages'])
        self.assertTrue(windows['nsis']['displayLanguageSelector'])
        self.assertIn('pt-BR', windows['wix']['language'])

    def test_installer_retina_dimensions(self):
        result = subprocess.run(['tiffutil', '-info', str(ROOT / 'src-tauri/dmg/installer-background.tiff')],
                                check=True, capture_output=True, text=True)
        text = result.stdout + result.stderr
        self.assertEqual(re.findall(r'Image Width: (\d+) Image Length: (\d+)', text),
                         [('768', '512'), ('1536', '1024')])
        self.assertEqual(re.findall(r'Resolution: ([\d.]+), ([\d.]+)', text), [('72', '72'), ('144', '144')])


if __name__ == '__main__':
    unittest.main()
