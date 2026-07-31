
local _, addon = ...

-- [ MODULE ] ----------------------------------------------------------------------------------------------------------
local Combat = {}
addon.PortalCombat = Combat

function Combat.CanInteract()
    if InCombatLockdown() then return false end
    if C_InstanceEncounter.IsEncounterInProgress() then return false end
    return true
end

function Combat.UpdateState(ctx)
    local dock = ctx.dock
    if not dock then return end

    local state = ctx.state
    local inCombatOrEncounter = InCombatLockdown() or C_InstanceEncounter.IsEncounterInProgress()

    if inCombatOrEncounter then
        -- REGEN_DISABLED fires just before lockdown; only Hide() while the secure call is still legal.
        if not InCombatLockdown() then
            dock:Hide()
        end
        state.isEditModeActive = false
        state.isMouseOver = false
        addon.PortalNavigation.HideSearch()
        addon.PortalNavigation.ClearSearchBuffer()
    else
        dock:Show()
        -- Re-assert the real visibility state; a flat alpha/mouse reset here would outrank a live pet-battle,
        -- vehicle or mounted hide that is still in effect when the fight ends.
        ctx.plugin:UpdateVisibility()
        addon.PortalNavigation.RestorePropagationDefault()
        if ctx.IsCursorOverDock() then
            state.isMouseOver = true
            addon.PortalNavigation.ShowSearch()
        end
        if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
            state.isEditModeActive = true
        end
    end
end
