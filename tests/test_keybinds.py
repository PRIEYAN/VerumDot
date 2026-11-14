"""Keybinding parsing can reuse unrelated formatter/classifier implementations."""
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib/python'))
from hyprrice.keybinds import Bind, CheatSheet, ConfigReader, read_config


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


    def test_lua_config_binds_resolve_through_requires_loops_and_submaps(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'conf').mkdir()
            (root/'conf'/'apps.lua').write_text('return { term = "kitty" }\n')
            (root/'hyprland.lua').write_text(
                'local apps = require("conf.apps")\n'
                'hl.on("hyprland.start", function() error("autostart must not run") end)\n'
                'hl.bind("SUPER + T", hl.dsp.exec_cmd(apps.term))\n'
                'hl.bind("SUPER + Return", hl.dsp.exec_cmd(apps.term))\n'
                'for i = 1, 2 do hl.bind("SUPER + " .. i, hl.dsp.focus({ workspace = tostring(i) })) end\n'
                'hl.bind("SUPER + Q", hl.dsp.window.close())\n'
                'hl.define_submap("calendar", function()\n'
                '  hl.bind("escape", function()\n'
                '    hl.dispatch(hl.dsp.exec_cmd("eww close calendar"))\n'
                '    hl.dispatch(hl.dsp.submap("reset"))\n'
                '  end)\n'
                'end)\n'
                'hl.window_rule({ match = { class = "x" }, float = true }):set_enabled(false)\n')
            sections = CheatSheet(read_config(str(root/'hyprland.lua'))).sections()
        self.assertEqual(sections, [
            {'title': 'Apps', 'items': [
                {'keys': [['Super', 'T'], ['Super', 'Enter']], 'action': 'Terminal (kitty)'}]},
            {'title': 'Windows', 'items': [
                {'keys': [['Super', 'Q']], 'action': 'Close active window'}]},
            {'title': 'Workspaces', 'items': [
                {'keys': [['Super', '1']], 'action': 'Workspace 1'},
                {'keys': [['Super', '2']], 'action': 'Workspace 2'}]},
            {'title': 'Calendar', 'items': [
                {'keys': [['Esc']], 'action': 'Close the calendar'}]},
        ])

    def test_shipped_lua_config_matches_its_legacy_cheat_sheet(self):
        root = Path(__file__).resolve().parents[1]
        # Before the migration the legacy entry is at the top; after it,
        # scripts/hyprland-lua-update.sh parks it under legacy/.
        conf = next((c for c in (root/'hyprland.conf', root/'legacy'/'hyprland.conf') if c.is_file()), None)
        if conf is None or not (root/'hyprland.lua').is_file():
            self.skipTest('needs both the Lua config and the legacy hyprland.conf')
        legacy = CheatSheet(read_config(str(conf))).sections()
        lua = CheatSheet(read_config(str(root/'hyprland.lua'))).sections()
        self.assertEqual(lua, legacy)


if __name__ == '__main__':
    unittest.main()
