"""Keybinding parsing can reuse unrelated formatter/classifier implementations."""
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib/python'))
from hyprrice.keybinds import Bind, CheatSheet, ConfigReader


class CustomClassifier:
    def __bool__(self):
        return False

    def classify(self, dispatcher, args):
        return 'Custom', f'{dispatcher}: {args}'


class CustomFormatter:
    def __bool__(self):
        return False

    def chord(self, modifiers, key):
        return (modifiers.lower(), key.lower())


class KeybindTests(unittest.TestCase):
    def test_falsey_collaborators_are_respected_across_included_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'main.conf').write_text('$app = browser\nsource = ./binds.conf\n')
            (root/'binds.conf').write_text('source = ./main.conf\nbind = SUPER, W, exec, $app\n')
            binds = ConfigReader(CustomClassifier(), CustomFormatter()).read(str(root/'main.conf'))
        self.assertEqual(binds, [Bind('Custom', ('super', 'w'), 'exec: browser')])

    def test_default_reader_and_sheet_keep_existing_output_contract(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory)/'main.conf'
            config.write_text('bind = SUPER, T, exec, kitty\nbind = SUPER, Return, exec, kitty\n')
            sections = CheatSheet(ConfigReader().read(str(config))).sections()
        self.assertEqual(sections, [{'title': 'Apps', 'items': [
            {'keys': [['Super', 'T'], ['Super', 'Enter']], 'action': 'Terminal (kitty)'}]}])


if __name__ == '__main__':
    unittest.main()
