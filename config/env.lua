-- Wayland and optional NVIDIA environment helpers.
local settings = require("config.settings")

hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")
if settings.nvidia then
    hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
end

-- Route Qt apps (Dolphin, etc.) through qt6ct so the pure-black PureBlack
-- color scheme + translucent Kvantum theme (PureBlackGlass) apply.
-- NOTE: AnyDesk inherits these and renders broken widgets (blank checkboxes/
-- radios/buttons) since it doesn't expect Kvantum styling hooks. It has a
-- ~/.local/share/applications/anydesk.desktop override that launches it via
-- scripts/anydesk-launch.sh, which unsets these two vars just for AnyDesk.
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("QT_STYLE_OVERRIDE", "kvantum")

-- Force dark GTK theme for nm-connection-editor, blueman-manager, etc.
hl.env("GTK_THEME", "Adwaita:dark")

-- Custom wallpaper folder, for scripts launched by Hyprland.
if settings.wallpaper_dir then
    hl.env("HYPR_WALLPAPER_DIR", settings.wallpaper_dir)
end
