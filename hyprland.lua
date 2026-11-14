-- VerumDot — Hyprland entry point (Lua config).
--
-- Hyprland loads this file instead of hyprland.conf whenever it exists
-- ("[cfg] Using lua config found at ..."). Each concern lives in its own
-- module under config/, loaded in the same order the old hyprland.conf /
-- hypr.conf pair applied them. See LUA_MIGRATION.md for what changed.
--
-- Validate without touching the running session:
--     Hyprland --verify-config -c ~/.config/hypr/hyprland.lua

require("config.env")
require("config.monitors")
require("config.look")
require("config.input")
require("config.rules")
require("config.binds")
require("config.autostart")
