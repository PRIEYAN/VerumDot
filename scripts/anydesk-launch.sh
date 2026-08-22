#!/bin/bash
# AnyDesk links against system libgtk-3, so GTK theming is the only lever we
# have on its chrome. The Qt vars are unset because AnyDesk's widgets render
# blank (empty checkboxes/radios/buttons) when Kvantum styling is forced onto
# a GTK app; dark styling comes from GTK instead.
unset QT_QPA_PLATFORMTHEME
unset QT_STYLE_OVERRIDE

# Force the dark Adwaita variant. AnyDesk also has its own theme setting
# (Settings -> Appearance -> Theme -> Dark Mode, persisted as ad.ui.theme in
# ~/.anydesk/user.conf); the panels it custom-draws only follow that setting,
# not GTK CSS.
export GTK_THEME=Adwaita:dark
export GTK_APPLICATION_PREFER_DARK_THEME=1

exec /usr/bin/anydesk "$@"
