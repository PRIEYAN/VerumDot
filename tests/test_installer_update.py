"""Update lifecycle tests; package and service actions stay inside shell stubs."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class InstallerUpdateTest(unittest.TestCase):
    def run_shell(self, body):
        with tempfile.TemporaryDirectory() as tmp:
            result = subprocess.run(
                ['bash', '-c', 'source <(sed \'$d\' setup.sh)\n'
                 'ANIM=0; COLOR=0; init_style\n'
                 'INSTALL_STATE="$TEST_ROOT/state.json"\n'
                 'LOG="$TEST_ROOT/log"\n' + body],
                cwd=REPO, env={**os.environ, 'TEST_ROOT': tmp},
                text=True, capture_output=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            return result.stdout

    def test_update_installs_only_missing_requirements(self):
        output = self.run_shell('''
MODE=update; PACMAN_LIST=(existing new); AUR_LIST=(existing-aur new-aur)
FACT_AUR=yay
pacman() { [[ "$1 $2" == '-Qq existing' || "$1 $2" == '-Qq existing-aur' ]]; }
sudo() { printf 'TRANSACTION %s\\n' "$*"; }
yay() { printf 'AUR %s\\n' "$*"; }
run_bg() { shift; "$@"; }; run_fg() { shift; "$@"; }
install_packages
''')
        self.assertIn('TRANSACTION pacman -Syu --needed new', output)
        self.assertIn('AUR -S --needed new-aur', output)
        self.assertNotIn('--noconfirm existing', output)

    def test_no_transaction_when_requirements_already_present(self):
        self.run_shell('''
MODE=update; PACMAN_LIST=(existing); AUR_LIST=(existing-aur)
pacman() { return 0; }; run_bg() { exit 91; }; run_fg() { exit 92; }
install_packages
''')

    def test_profile_and_pending_retirements_round_trip(self):
        self.run_shell('''
SEL_GROUPS=(audio apps); PICK_TERM=foot; PICK_BROWSER=chromium
PACMAN_LIST=(current); AUR_LIST=(); RETIRED_PACKAGES=(old)
MANAGED_SERVICES=(user:pipewire); RETIRED_SERVICES=(system:old-daemon)
save_install_state || exit
SEL_GROUPS=(); PICK_TERM=kitty; PICK_BROWSER=firefox
load_update_state || exit
[[ "$PICK_TERM $PICK_BROWSER" == 'foot chromium' ]] || exit 1
[[ "${SEL_GROUPS[*]}" == 'audio apps' ]] || exit 1
[[ "${PREVIOUS_PACKAGES[*]}" == 'current old' ]] || exit 1
[[ "${PREVIOUS_SERVICES[*]}" == 'user:pipewire system:old-daemon' ]]
''')

    def test_retired_packages_require_opt_in_and_are_not_recursive(self):
        output = self.run_shell('''
MODE=update; RETIRED_PACKAGES=(keep remove); RETIRED_SERVICES=()
pacman() { return 0; }
ui_yn() { [[ "$1" == *'remove?' ]]; }
sudo() { printf 'REMOVE %s\\n' "$*"; }
run_fg() { shift; "$@"; }
cleanup_retired || exit
[[ "${RETIRED_PACKAGES[*]}" == keep ]]
''')
        self.assertIn('REMOVE pacman -R -- remove', output)
        self.assertNotIn('-Rns', output)

    def test_service_retirement_requires_approval(self):
        output = self.run_shell('''
MODE=update; DO_SERVICES=1; RETIRED_PACKAGES=()
RETIRED_SERVICES=(user:old system:keep)
ui_yn() { [[ "$1" == *'user:old?' ]]; }
systemctl() { [[ "$*" == '--user disable --now old' ]] || exit 94; }
sudo() { exit 93; }
cleanup_retired || exit
[[ "${RETIRED_SERVICES[*]}" == system:keep ]] || exit 1
printf 'Disabled old\\n'
''')
        self.assertIn('Disabled old', output)

    def test_settings_merge_keeps_machine_values_and_new_defaults(self):
        self.run_shell('''
TARGET="$TEST_ROOT/target"; mkdir -p "$TARGET/config"
printf 'return {\\n terminal = "kitty",\\n new_option = true,\\n}\\n' > "$TARGET/config/settings.lua"
UPDATE_SETTINGS=$'return {\\n terminal = "foot",\\n}\\n'
restore_update_settings || exit
 grep -q 'terminal = "foot"' "$TARGET/config/settings.lua" || exit 1
 grep -q 'new_option = true' "$TARGET/config/settings.lua"
''')

    def test_retirement_plan_uses_only_previous_manifest(self):
        self.run_shell(''' 
PACMAN_LIST=(current); AUR_LIST=(current-aur)
PREVIOUS_PACKAGES=(current current-aur retired gone)
PREVIOUS_SERVICES=(user:pipewire system:retired)
SEL_GROUPS=()
pacman() { [[ "$2" != gone ]]; }
plan_retirements
[[ "${RETIRED_PACKAGES[*]}" == retired ]] || exit 1
[[ "${RETIRED_SERVICES[*]}" == system:retired ]]
''')

    def test_unattended_cleanup_keeps_everything(self):
        self.run_shell('''
MODE=update; DO_SERVICES=1
RETIRED_PACKAGES=(old); RETIRED_SERVICES=(system:old)
pacman() { return 0; }; sudo() { exit 95; }; systemctl() { exit 96; }
cleanup_retired || exit
[[ "${RETIRED_PACKAGES[*]}" == old ]] || exit 1
[[ "${RETIRED_SERVICES[*]}" == system:old ]]
''')

    def test_failed_removal_stays_in_record(self):
        self.run_shell('''
MODE=update; RETIRED_PACKAGES=(required-elsewhere); RETIRED_SERVICES=()
pacman() { return 0; }; ui_yn() { return 0; }; run_fg() { return 1; }
cleanup_retired || exit
[[ "${RETIRED_PACKAGES[*]}" == required-elsewhere ]]
''')

    def test_existing_app_bindings_determine_dependency_choices(self):
        self.run_shell('''
UPDATE_SETTINGS=$'return {\\n terminal = "foot",\\n browser = "chromium",\\n files = "thunar",\\n editor = "foot -e nvim",\\n}\\n'
adopt_update_settings || exit
SEL_GROUPS=(apps); DO_NVIM=0; build_pkg_lists
[[ "$PICK_TERM $PICK_BROWSER $PICK_FILES $PICK_EDITOR" == "foot chromium thunar nvim" ]] || exit 1
printf '%s\\n' "${PACMAN_LIST[@]}" | grep -qx thunar || exit 1
! printf '%s\\n' "${PACMAN_LIST[@]}" | grep -qx firefox
''')

    def test_config_only_skips_missing_optional_system_units(self):
        self.run_shell('''
DO_PACKAGES=0; DO_SERVICES=1; SUDO_OK=1; SEL_GROUPS=(power)
systemctl() { [[ "$1" != cat ]]; }
sudo() { exit 99; }
apply_services || exit
[[ "${MANAGED_SERVICES[*]}" == "user:pipewire user:pipewire-pulse user:wireplumber" ]]
''')

    def test_real_deployment_backs_up_old_files_and_repairs_links(self):
        self.run_shell('''
RICE_SRC="$PWD"; XDG_CFG="$TEST_ROOT/config"; XDG_STATE_HOME="$TEST_ROOT/state"
TARGET="$XDG_CFG/hypr"; WAYBAR_CFG="$XDG_CFG/waybar"
WALLPAPER_DIR="$TEST_ROOT/wallpapers"
FACT_EXISTING=1; FACT_INPLACE=0
mkdir -p "$TARGET/config"
printf old > "$TARGET/old-marker"
UPDATE_SETTINGS=$'return {\\n terminal = "foot",\\n}\\n'
deploy_files || exit
restore_update_settings || exit
[[ -f "$TARGET.bak.$STAMP/old-marker" ]] || exit 1
[[ ! -e "$TARGET/old-marker" ]] || exit 1
[[ "$WAYBAR_CFG/style.css" -ef "$TARGET/apps/waybar/style.css" ]] || exit 1
[[ "$TARGET/apps/quickshell/controlcenter/shared" -ef "$TARGET/apps/quickshell/shared" ]] || exit 1
grep -q 'terminal = "foot"' "$TARGET/config/settings.lua"
''')

    def test_update_main_preserves_settings_and_orders_service_transition(self):
        self.run_shell('''
HOME="$TEST_ROOT/home"; XDG_CFG="$HOME/.config"
TARGET="$XDG_CFG/hypr"; RICE_SRC="$TEST_ROOT/source"
LOG="$TEST_ROOT/cache/log"
mkdir -p "$TARGET/config" "$RICE_SRC"
printf 'return {\\n terminal = "foot",\\n}\\n' > "$TARGET/config/settings.lua"
id() { printf 1000; }; clear() { :; }; banner() { :; }
preflight() { FACT_EXISTING=1; FACT_INPLACE=0; FACT_PACMAN=1; }
sudo_begin() { SUDO_OK=1; }; sudo_end() { :; }
show_plan() { build_pkg_lists; plan_retirements; }
install_packages() { :; }; verify_quickshell() { :; }
deploy_files() { printf 'return {\\n terminal = "kitty",\\n new_option = true,\\n}\\n' > "$TARGET/config/settings.lua"; }
personalise() { exit 97; }; deploy_nvim() { :; }; apply_theme() { :; }
cleanup_retired_services() { printf retired > "$TEST_ROOT/order"; }
apply_services() { [[ "$(cat "$TEST_ROOT/order")" == retired ]] || exit 98; }
apply_lid() { :; }; apply_fan() { :; }; finish() { :; }
main --update --no-theme --no-lid --no-nvim
[[ -s "$INSTALL_STATE" ]] || exit 1
grep -q 'terminal = "foot"' "$TARGET/config/settings.lua" || exit 1
grep -q 'new_option = true' "$TARGET/config/settings.lua"
''')


if __name__ == '__main__':
    unittest.main()
