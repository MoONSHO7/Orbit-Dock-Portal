local _, addon = ...
local Orbit = Orbit
local L = Orbit.L

local wipe = wipe

-- [ MODULE ] ----------------------------------------------------------------------------------------
local Commands = {}
addon.PortalCommands = Commands

function Commands.Handle(ctx, cmd)
    if cmd ~= "scan" then return end
    wipe(ctx.state.mythicPlusCache)
    if addon.PortalCombat.CanInteract() then
        ctx.RefreshDock()
    end
    Orbit:Print(L.CMD_PORTAL_SCAN_DONE)
end
