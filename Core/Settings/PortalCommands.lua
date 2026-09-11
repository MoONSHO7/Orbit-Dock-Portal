local _, addon = ...
local Services = addon.PortalServices
local L = addon.L

local wipe = wipe

-- [ MODULE ] ----------------------------------------------------------------------------------------------------------
local Commands = {}
addon.PortalCommands = Commands

function Commands.Handle(ctx, cmd)
    if cmd ~= "scan" then
        return
    end
    wipe(ctx.state.mythicPlusCache)
    if addon.PortalCombat.CanInteract() then
        ctx.Refresh()
    end
    Services.Message(L.CMD_PORTAL_SCAN_DONE)
end
