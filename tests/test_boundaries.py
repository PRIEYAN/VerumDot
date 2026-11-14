"""Dependency graph and failure-path tests with no real hardware mutations."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ShellBoundaryTests(unittest.TestCase):
    def run_shell(self, body):
        with tempfile.TemporaryDirectory() as directory:
            env = dict(os.environ, XDG_STATE_HOME=directory+'/state', XDG_DATA_HOME=directory+'/data',
                       XDG_CACHE_HOME=directory+'/cache', XDG_RUNTIME_DIR=directory+'/run',
                       TEST_EVENTS=directory+'/events', HYPR_LOG_LEVEL='silent')
            result = subprocess.run(['bash', '-c', 'set -e\nsource lib/bootstrap.sh\n'+body],
                                    cwd=ROOT, env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_failed_power_change_does_not_save_or_notify(self):
        self.run_shell('''hypr::use domain/power
state::set "$POWER_STATE_KEY" normal
guard::has() { [[ $1 == powerprofilesctl ]]; }
proc::quiet() { return 1; }
fan::apply() { echo fan >>"$TEST_EVENTS"; }
waybar::refresh() { echo refresh >>"$TEST_EVENTS"; }
notify::transient() { echo notify >>"$TEST_EVENTS"; }
if power::set_mode performance; then exit 9; fi
[[ $(state::get "$POWER_STATE_KEY" missing) == normal ]]
[[ ! -e $TEST_EVENTS ]]
''')

    def test_successful_power_change_saves_before_dependent_actions(self):
        self.run_shell('''hypr::use domain/power
guard::has() { [[ $1 == powerprofilesctl ]]; }
proc::quiet() { [[ $* == 'powerprofilesctl set performance' ]]; }
fan::apply() { [[ $(state::get "$POWER_STATE_KEY" missing) == performance ]]; echo fan >>"$TEST_EVENTS"; }
waybar::refresh() { echo refresh >>"$TEST_EVENTS"; }
notify::transient() { echo notify >>"$TEST_EVENTS"; }
power::set_mode performance
[[ $(cat "$TEST_EVENTS") == $'fan\\nrefresh\\nnotify' ]]
''')

    def test_missing_backend_and_invalid_modes_fail_without_state(self):
        self.run_shell('''hypr::use domain/powerprofile
guard::has() { return 1; }
if powerprofile::set battery; then exit 9; fi
if powerprofile::set invalid; then exit 9; fi
[[ $(state::get "$POWER_STATE_KEY" missing) == missing ]]
''')

    def test_cpupower_fallback_uses_requested_governor(self):
        self.run_shell('''hypr::use domain/powerprofile
guard::has() { [[ $1 == cpupower ]]; }
proc::quiet() { [[ $* == 'sudo cpupower frequency-set -g powersave' ]]; }
powerprofile::set battery
[[ $(state::get "$POWER_STATE_KEY" missing) == battery ]]
''')

    def test_profile_reads_prefer_backend_over_cache(self):
        self.run_shell('''hypr::use domain/powerprofile
state::set "$POWER_STATE_KEY" battery
guard::has() { return 0; }
proc::capture() { printf balanced; }
[[ $(powerprofile::mode) == normal ]]
proc::capture() { return 1; }
[[ $(powerprofile::mode) == battery ]]
''')

    def test_fan_policy_is_pure_and_does_not_load_power_workflow(self):
        self.run_shell('''hypr::use domain/fan
! declare -F power::set_mode >/dev/null
for profile in normal battery performance; do
  [[ $(fan::resolve_pwm max "$profile") == 0 ]]
  [[ $(fan::resolve_pwm normal "$profile") == 2 ]]
done
[[ $(fan::resolve_pwm auto performance) == 0 ]]
[[ $(fan::resolve_pwm auto normal) == 2 ]]
[[ $(fan::resolve_pwm auto battery) == 2 ]]
if fan::resolve_pwm invalid normal; then exit 9; fi
''')

    def test_audio_failure_is_not_hidden_by_repaint(self):
        self.run_shell('''hypr::use domain/audio
proc::first_available() { return 7; }
waybar::refresh() { echo refresh >>"$TEST_EVENTS"; }
for operation in 'audio::set_volume 30' 'audio::step_volume up' audio::toggle_mute audio::toggle_mic; do
  if $operation; then exit 9; else [[ $? == 7 ]]; fi
done
[[ ! -e $TEST_EVENTS ]]
''')

    def test_audio_success_repaints(self):
        self.run_shell('''hypr::use domain/audio
proc::first_available() { return 0; }
waybar::refresh() { echo "$1" >>"$TEST_EVENTS"; }
audio::set_volume 30
audio::toggle_mic
[[ $(cat "$TEST_EVENTS") == $'volume\\nmic' ]]
''')

    def test_library_dependency_graph_has_no_cycles_or_upward_core_imports(self):
        graph = {}
        for path in (ROOT/'lib').glob('*/*.sh'):
            module = path.relative_to(ROOT/'lib').with_suffix('').as_posix()
            graph[module] = [dep for line in path.read_text().splitlines() if line.startswith('hypr::use ')
                             for dep in line.split()[1:] if '/' in dep]
        visited = set()
        def visit(module, stack):
            self.assertNotIn(module, stack, f'cycle: {stack} -> {module}')
            if module in visited:
                return
            for dependency in graph.get(module, []):
                self.assertIn(dependency, graph)
                if module.startswith(('core/', 'os/')):
                    self.assertFalse(dependency.startswith(('ui/', 'domain/')), (module, dependency))
                visit(dependency, stack + [module])
            visited.add(module)
        for module in graph:
            visit(module, [])


if __name__ == '__main__':
    unittest.main()
