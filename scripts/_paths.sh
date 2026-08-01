# Shared path helpers for this rice.
# Source from any script under scripts/ or scripts/*/:
#   # shellcheck source=/dev/null
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"          # scripts/
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/_paths.sh"      # scripts/<subdir>/
#
# Prefer the rice that contains this file (portable clone), fall back to XDG.

_paths_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HYPR_DIR="$(cd "${_paths_here}/.." && pwd)"
: "${XDG_CONFIG_HOME:=${HOME}/.config}"
: "${XDG_CACHE_HOME:=${HOME}/.cache}"
: "${XDG_DATA_HOME:=${HOME}/.local/share}"

HYPR_SCRIPTS="${HYPR_DIR}/scripts"
HYPR_APPS="${HYPR_DIR}/apps"
HYPR_ROFI="${HYPR_APPS}/rofi"
HYPR_EWW="${HYPR_APPS}/eww"
HYPR_WAYBAR="${HYPR_APPS}/waybar"
HYPR_WAYBAR_SCRIPTS="${HYPR_WAYBAR}/scripts"

unset _paths_here
