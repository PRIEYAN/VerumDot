-- Touchpad gestures.

local scripts = os.getenv("HOME") .. "/.config/hypr/scripts"

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- 4-finger swipe up: open the hidden workspace, only from workspace 1.
-- 4-finger swipe down: close it again (always allowed).
hl.gesture({
    fingers = 4, direction = "up",
    action = function() hl.dispatch(hl.dsp.exec_cmd(scripts .. "/hidden-workspace-open.sh")) end,
})
hl.gesture({
    fingers = 4, direction = "down",
    action = function() hl.dispatch(hl.dsp.exec_cmd(scripts .. "/hidden-workspace-close.sh")) end,
})

-- Hair-trigger workspace swipe: a short flick commits instead of requiring a
-- full edge-to-edge drag.
--   distance            - px of travel that equals one whole workspace
--   cancel_ratio        - fraction of that distance you must pass to commit;
--                         below it the swipe snaps back
--   min_speed_to_force  - flick speed that switches regardless of distance
hl.config({
    gestures = {
        workspace_swipe_distance           = 120,
        workspace_swipe_cancel_ratio       = 0.15,
        workspace_swipe_min_speed_to_force = 5,
        workspace_swipe_direction_lock     = false,
        -- Swiping right off the last workspace brings a new one into existence.
        workspace_swipe_create_new         = true,
    },
})
