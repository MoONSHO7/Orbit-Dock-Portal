local _, addon = ...

-- [ MODULE ] ----------------------------------------------------------------------------------------------------------
local Combat = {}
addon.PortalCombat = Combat

function Combat.CanInteract()
    if InCombatLockdown() then
        return false
    end
    if C_InstanceEncounter.IsEncounterInProgress() then
        return false
    end
    return true
end

function Combat.UpdateState(ctx)
    local frame = ctx.frame
    if not frame then
        return
    end

    local state = ctx.state
    local inCombatOrEncounter = InCombatLockdown() or C_InstanceEncounter.IsEncounterInProgress()

    if inCombatOrEncounter then
        -- The frame's secure visibility driver owns combat hiding; encounter-only suppression remains legal here.
        if not InCombatLockdown() then
            frame:Hide()
        end
        state.isEditModeActive = false
        state.isMouseOver = false
        addon.PortalNavigation.HideSearch()
        addon.PortalNavigation.ClearSearchBuffer()
    else
        ctx.plugin:UpdateVisibility()
        addon.PortalNavigation.RestorePropagationDefault()
        if ctx.IsCursorOverFrame() then
            state.isMouseOver = true
            addon.PortalNavigation.ShowSearch()
        end
    end
end
