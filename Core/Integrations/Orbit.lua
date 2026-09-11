local _, addon = ...
local Orbit = Orbit
local Engine = Orbit and Orbit.Engine
if not Engine or type(Orbit.ExternalUIHost) ~= "table" or Orbit.ExternalUIHost.legacyPluginVersion ~= 1 then
    return
end

local Services = addon.PortalServices
local Bridge = {}
addon.PortalOrbit = Bridge
local COMPONENT_KEYS = { "DungeonScore", "DungeonShort", "FavouriteStar", "Timer" }
local SELECTION_OUTSET = 5

function Bridge.CreatePlugin()
    local plugin = Orbit:RegisterPlugin(
        "Orbit-Portal",
        "Orbit_Portal",
        { defaults = CopyTable(addon.PortalDefaults), liveToggle = true, displayName = addon.L.PLU_VE_PORTAL }
    )
    plugin.canvasMode = true
    for _, key in ipairs(COMPONENT_KEYS) do
        Engine.CanvasMode.ComponentCatalog:RegisterDeclared(key)
    end
    return plugin
end

function Services.GetFontPath()
    local font = Orbit:GetTheme("Font")
    local media = LibStub and LibStub("LibSharedMedia-3.0", true)
    return (media and font and media:Fetch("font", font, true)) or STANDARD_TEXT_FONT
end

function Services.ApplyFontOverrides(region, overrides, size, path)
    Engine.OverrideUtils.ApplyFontOverrides(region, overrides, size, path)
end

function Services.ApplyTimerOverrides(region, overrides, size, path)
    Engine.OverrideUtils.ApplyOverrides(region, overrides, { fontSize = size, fontPath = path })
end

function Services.ApplyTextPosition(region, parent, position, anchor, x, y)
    Engine.PositionUtils.ApplyTextPosition(region, parent, position, anchor, x, y)
end

function Services.SetFont(region, path, size, flags)
    Orbit.Skin:SetFontWithShadow(region, path, size, flags)
end

function Services.DetectOrientation(frame)
    return Engine.FrameOrientation:DetectOrientation(frame)
end

function Bridge.AttachFrame(ctx)
    local frame, plugin = ctx.frame, ctx.plugin
    frame.orbitNoSnap = true
    frame.orbitSelectionOutset = SELECTION_OUTSET
    Engine.FramePersistence:AttachSettingsListener(frame, plugin, 1)
    Engine.FrameOrientation:RegisterCallback(frame, function()
        if not addon.PortalCombat.CanInteract() then
            return
        end
        local x, y = frame:GetCenter()
        ctx.Refresh()
        if frame.orbitIsDragging and x and y then
            local left, bottom = Services.pixel:SnapPosition(
                x - frame:GetWidth() / 2,
                y - frame:GetHeight() / 2,
                "BOTTOMLEFT",
                frame:GetWidth(),
                frame:GetHeight(),
                frame:GetEffectiveScale()
            )
            frame:ClearAllPoints()
            frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
        end
    end)
    Engine.FramePersistence:RestorePosition(frame, plugin, 1)
end

function Bridge.Enable(ctx)
    Orbit.OOCFadeMixin:ApplyOOCFade(ctx.frame, ctx.plugin, 1)
    ctx.plugin:RegisterStandardEvents()
    ctx.plugin:RegisterVisibilityEvents()
    Engine.EditMode:RegisterCallbacks({
        Enter = function()
            ctx.state.isEditModeActive = addon.PortalCombat.CanInteract()
            addon.PortalNavigation.HideSearch()
            if ctx.state.isEditModeActive then
                ctx.Refresh()
            end
        end,
        Exit = function()
            ctx.state.isEditModeActive = false
            ctx.RequestRefresh()
        end,
    }, Bridge, ctx.plugin)
end

function Bridge.Disable()
    Engine.EditMode:UnregisterCallbacks(Bridge)
end

function Bridge.EnterEditMode()
    Engine.EditMode:TryEnter()
end

function Bridge.IsEnabled()
    return Orbit:IsPluginEnabled("Orbit-Portal")
end

function Bridge.SetEnabled(enabled)
    Orbit:LiveTogglePlugin("Orbit-Portal", enabled)
end

function Bridge.ResetPosition(ctx)
    ctx.plugin:SetSetting(1, "Anchor", false)
    ctx.plugin:SetSetting(1, "Position", CopyTable(addon.PortalDefaults.Position))
    Engine.FramePersistence:RestorePosition(ctx.frame, ctx.plugin, 1)
    ctx.RequestRefresh()
end

function Bridge.UpdateVisibility(ctx, hidden)
    hidden = hidden
        or ctx.plugin:IsProfileSuppressed()
        or Orbit.VisibilityEngine:IsFrameMountedHidden(ctx.plugin.name, 1)
    Orbit.OOCFadeService:SetLifecycleHidden(ctx.frame, hidden)
    return hidden or ctx.frame.orbitHiddenByAlpha
end

function Bridge.RenderSettings(plugin, dialog, systemFrame, ctx)
    local builder = Engine.SchemaBuilder
    local tabs = addon.PortalSchema.Tabs(plugin, ctx)
    local labels = {}
    for _, tab in ipairs(tabs) do
        labels[#labels + 1] = tab.label
    end
    local schema = { controls = {}, extraButtons = {} }
    builder:SetTabRefreshCallback(dialog, plugin, systemFrame)
    local current = builder:AddSettingsTabs(schema, dialog, labels, labels[1])
    for _, tab in ipairs(tabs) do
        if tab.label == current then
            schema.controls = type(tab.controls) == "function" and tab.controls() or tab.controls
            break
        end
    end
    Engine.Config:Render(dialog, systemFrame, plugin, schema)
end
