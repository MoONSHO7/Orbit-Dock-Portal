-- PortalCommands.lua: /orbit portal slash command handler.

local _, addon = ...
local Orbit = Orbit
local L = Orbit.L

local wipe = wipe

-- [ MODULE ] ----------------------------------------------------------------------------------------
local Commands = {}
addon.PortalCommands = Commands

function Commands.Handle(ctx, cmd)
    cmd = cmd or ""
    if cmd == "scan" then
        wipe(ctx.state.mythicPlusCache)
        if addon.PortalCombat.CanInteract() then
            ctx.RefreshDock()
        end
        Orbit:Print(L.CMD_PORTAL_SCAN_DONE)
    else
        print(L.CMD_PORTAL_HEADER)
        print(L.CMD_PORTAL_HELP_SCAN)
    end
end
