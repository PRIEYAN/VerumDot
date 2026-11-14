-- hl-recorder.lua — run a Hyprland Lua config outside Hyprland and print its
-- binds, one per line, tab-separated:
--
--     submap  modifiers  key  dispatcher  args
--
-- Used by the SUPER+I cheat sheet (lib/python/hyprrice/keybinds.py). The
-- config is executed against a stub `hl` that records hl.bind() calls instead
-- of a parser guessing at Lua syntax, so loops, locals and helper functions
-- in the config all resolve exactly as Hyprland would resolve them.
--
-- Dispatchers are reported under their legacy hyprlang names (exec,
-- killactive, workspace, ...) so the existing classifier keeps one vocabulary.
--
--     lua hl-recorder.lua /path/to/hyprland.lua

local config = assert(arg[1], "usage: lua hl-recorder.lua <hyprland.lua>")
local dir = config:match("^(.*)/[^/]*$") or "."
package.path = dir .. "/?.lua;" .. dir .. "/?/init.lua;" .. package.path

-- A dispatcher made by hl.dsp.*(...) — remembers its path and first argument.
local DSP = {}

-- A stub that absorbs any field access or call: hl.layer_rule(...):set_enabled
-- and friends must not fail just because nothing here implements them.
local function sink()
    return setmetatable({}, {
        __index = function() return sink() end,
        __call  = function() return sink() end,
    })
end

local function namespace(path)
    return setmetatable({}, {
        __index = function(_, key) return namespace(path == "" and key or path .. "." .. key) end,
        __call  = function(_, arg1)
            return setmetatable({ path = path, arg = arg1 }, DSP)
        end,
    })
end

-- hl.dsp path + argument -> legacy (dispatcher, args).
local function legacy(d)
    local a = type(d.arg) == "table" and d.arg or {}
    local p = d.path
    if p == "exec_cmd" or p == "exec_raw" then return "exec", tostring(d.arg or "") end
    if p == "window.close" then return "killactive", "" end
    if p == "window.kill" then return "forcekillactive", "" end
    if p == "window.fullscreen" then return "fullscreen", "" end
    if p == "window.float" then return "togglefloating", "" end
    if p == "window.pin" then return "pin", "" end
    if p == "window.drag" then return "movewindow", "" end
    if p == "window.resize" and a.x == nil then return "resizewindow", "" end
    if p == "window.cycle_next" then return "focuswindow", a.next == false and "previous" or "next" end
    if p == "window.move" and a.workspace ~= nil then
        return a.follow == false and "movetoworkspacesilent" or "movetoworkspace", tostring(a.workspace)
    end
    if p == "focus" and a.workspace ~= nil then return "workspace", tostring(a.workspace) end
    if p == "focus" and a.direction ~= nil then return "movefocus", tostring(a.direction) end
    if p == "workspace.toggle_special" then return "togglespecialworkspace", tostring(d.arg or "") end
    if p == "submap" then return "submap", tostring(d.arg or "") end
    if p == "exit" then return "exit", "" end
    return p, ""
end

local submap = ""
local rows = {}

local function clean(s) return (tostring(s):gsub("[\t\n]", " ")) end

local function record(keys, dispatcher)
    -- A Lua function bind: run it with hl.dispatch recording, and describe
    -- the bind by the first thing it does that is not submap bookkeeping.
    if type(dispatcher) == "function" then
        local seen = {}
        local saved = hl.dispatch
        hl.dispatch = function(d) seen[#seen + 1] = d end
        pcall(dispatcher)
        hl.dispatch = saved
        dispatcher = nil
        for _, d in ipairs(seen) do
            if getmetatable(d) == DSP and d.path ~= "submap" then dispatcher = d; break end
        end
        dispatcher = dispatcher or seen[1]
    end
    local name, args = "lua", ""
    if getmetatable(dispatcher) == DSP then name, args = legacy(dispatcher) end

    -- "SUPER + CTRL + 1" -> mods "SUPER CTRL", key "1". A bare key has no mods.
    local parts = {}
    for token in keys:gmatch("[^+]+") do parts[#parts + 1] = token:match("^%s*(.-)%s*$") end
    local key = table.remove(parts) or ""
    rows[#rows + 1] = table.concat({
        clean(submap), clean(table.concat(parts, " ")), clean(key), clean(name), clean(args),
    }, "\t")
end

hl = setmetatable({
    dsp = namespace(""),
    bind = function(keys, dispatcher)
        local ok, err = pcall(record, keys, dispatcher)
        if not ok then io.stderr:write("hl-recorder: ", tostring(err), "\n") end
        return sink()
    end,
    define_submap = function(name, reset_or_fn, fn)
        local body = type(reset_or_fn) == "function" and reset_or_fn or fn
        local outer = submap
        submap = name
        if body then body() end
        submap = outer
    end,
    dispatch = function() end,
    -- Startup hooks and timers must not run here: they launch the desktop.
    on = function() return sink() end,
    timer = function() return sink() end,
    get_config = function() return nil end,
}, { __index = function() return sink() end })

dofile(config)

for _, row in ipairs(rows) do io.write(row, "\n") end
