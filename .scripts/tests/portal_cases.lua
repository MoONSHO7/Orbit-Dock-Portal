local scenario = ...
local Plugin, Boot, Store, ctx = addon.Portal, addon.PortalBoot, addon.PortalStore, addon.PortalContext
local function Check(condition, message)
    assert(condition, message)
end
local originalStore = OrbitPortalDB
addon.PortalScanner.GetOrderedList = function()
    return { { type = "spell", spellID = 123, name = "Fixture Portal", category = "CLASS", icon = 134400 } }
end
addon.PortalScanner.RequestHousingData = function() end
addon.PortalScanner.RefreshCooldowns = function() end
if scenario == "loaderror" or scenario == "movementerror" then
    allowedErrors = 1
    if scenario == "loaderror" then
        local onLoad = Plugin.OnLoad
        Plugin.OnLoad = function(self)
            onLoad(self)
            error("injected constructor failure")
        end
    else
        local create = addon.LibOrbitUI.Movement.Create
        addon.LibOrbitUI.Movement.Create = function(self, ...)
            create(self, ...)
            error("injected movement failure")
        end
    end
end
Emit("ADDON_LOADED", "Orbit_Portal")
Emit("PLAYER_LOGIN")
Check(settingsCategory ~= nil, "direct settings registration")
if scenario == "loaderror" or scenario == "movementerror" then
    Check(#errors == 1 and frameCreations == 1 and not Plugin._portalActive, "constructor failure reported once")
    local initialCount = #frames
    for _ = 1, 3 do
        Boot.Apply()
        Emit("PLAYER_REGEN_ENABLED")
        FlushTimers()
    end
    Check(
        #errors == 1 and frameCreations == 1 and #frames == initialCount,
        "failed initialization never reconstructs partial graph"
    )
    Boot.ShowSettings()
    Boot.ResetPosition()
    Check(messages[#messages]:find(addon.L.MSG_PORTAL_NOT_READY, 1, true), "failed feature reports inactive state")
    return
end
if scenario == "future" then
    Check(OrbitPortalDB == originalStore and OrbitPortalDB.marker == "untouched", "future DB untouched")
    Check(not Plugin._portalConstructed and not OrbitPortalFrame, "unsupported store constructs no secure frame")
    SlashCmdList.ORBITPORTAL("status")
    Check(messages[#messages]:find(addon.L.MSG_PORTAL_UNSUPPORTED_STORE, 1, true), "status reports unsupported store")
    return
end
if scenario == "disabled" then
    Check(not Plugin._portalConstructed and frameCreations == 0 and mapRequests == 0, "disabled first boot stays inert")
    Boot.ShowSettings()
    Check(OrbitPortalSettings:IsShown(), "disabled product has usable settings")
    Store:Set("Enabled", true)
    Boot.Apply()
elseif scenario == "blocked" then
    Check(not Plugin._portalConstructed and frameCreations == 0, "blocked startup defers construction")
    SetCombat(false)
elseif scenario == "legacy" then
    Check(OrbitPortalDB == nil and addon.PortalOrbit ~= nil, "legacy mode never hydrates standalone DB")
    Check(not Plugin._portalConstructed, "host lifecycle owns legacy construction")
    Plugin:OnLoad()
    Plugin:OnEnable()
end
FlushTimers()
FlushTimers()
Check(Plugin._portalActive and Plugin.frame and #ctx.state.visibleIcons == 1, "initial frame painted")
Check(frameCreations == 1 and mapRequests == 1, "one constructor")
local firstIcon = ctx.state.visibleIcons[1]
Check(firstIcon:GetAttribute("type1") == "spell" and firstIcon:GetAttribute("spell") == 123, "secure spell configured")
firstIcon.scripts.PreClick(firstIcon, "RightButton", true)
firstIcon.scripts.PreClick(firstIcon, "RightButton", false)
Check(
    Plugin:GetSetting(1, "Favorites")["123"] == true and firstIcon:GetAttribute("type1") == "spell",
    "right-click down/up toggles once and preserves left action"
)
if scenario == "corrupt" then
    Check(OrbitPortalDB.profiles.default.settings.Position == "bad", "bad raw position retained")
    Check(
        Plugin:GetSetting(1, "Position").point == "LEFT" and Plugin:GetSetting(1, "MaxVisible") == 9,
        "invalid reads resolve defaults"
    )
end
if scenario ~= "legacy" then
    Check(addon.PortalOrbit == nil, "plain controller selected without compatible host")
    Store:Set("EnableKeyboardSearch", false)
    Store:Set("Spacing", 0)
    Check(Store:Get("EnableKeyboardSearch") == false and Store:Get("Spacing") == 0, "false and zero preserved")
    local favorites = Store:Get("Favorites")
    favorites.test = true
    Check(Store:Get("Favorites").test == nil, "table reads are defensive copies")
    Store:Set("Favorites", favorites)
    favorites.test = false
    Check(Store:Get("Favorites").test == true, "table writes are defensive copies")
    for _, case in ipairs({
        { "Position", "bad" },
        { "IconSize", 0 },
        { "MaxVisible", 4 },
        { "Spacing", 0 / 0 },
        { "Favorites", { bad = 1 } },
        { "Enabled", 1 },
        { "DisabledComponents", { {} } },
    }) do
        Check(not pcall(Store.Set, Store, case[1], case[2]), "invalid write rejected: " .. case[1])
    end
end
Boot.ShowSettings()
Check(OrbitPortalSettings:IsShown(), "direct standalone dialog rendered")
Check(
    OrbitPortalSettings.layout.Stack == addon.LibOrbitUI.Layout.Methods.Stack,
    "Portal dialog uses the shared layout implementation"
)
Check(
    OrbitPortalSettings.OrbitPanel.configPanelOwner == OrbitPortalSettings.renderer,
    "Portal dialog uses the shared panel owner"
)
Check(
    OrbitPortalSettings.Chrome.Background.atlas == "housing-basic-container"
        and OrbitPortalSettings:GetWidth() == addon.LibOrbitUI.Config.Defaults.Panel.DialogWidth,
    "Portal uses Orbit settings shell art and width"
)
local footer = OrbitPortalSettings.OrbitPanel.Footer
Check(
    #OrbitPortalSettings.layout.containerControls[footer] == 4 and footer:GetHeight() == 70,
    "Portal layout actions and close share the two-column footer"
)
OrbitPortalSettings:SelectTab("behaviours")
OrbitPortalSettings:SelectTab("categories")
Check(
    #OrbitPortalSettings.layout.containerControls[footer] == 1 and footer:GetHeight() == 44,
    "conditional footer rebuild removes layout actions"
)
Check(
    OrbitPortalSettings.controls[1].Label:GetJustifyH() == "LEFT",
    "Portal category checkbox uses native left-aligned label"
)
OrbitPortalSettings:SelectTab("layout")
local control = OrbitPortalSettings.spec.tabs[1].controls[1]
addon.LibOrbitUI.Config.CommitValue(OrbitPortalSettings.spec, control, false)
Check(not Plugin._portalActive, "dialog enablement disables product")
addon.LibOrbitUI.Config.CommitValue(OrbitPortalSettings.spec, control, true)
FlushTimers()
local frameCount = #frames
for _ = 1, 20 do
    addon.LibOrbitUI.Config.CommitValue(OrbitPortalSettings.spec, control, false)
    addon.LibOrbitUI.Config.CommitValue(OrbitPortalSettings.spec, control, true)
    FlushTimers()
end
Check(
    #frames == frameCount and frameCreations == 1 and mapRequests == 1,
    "toggle cycles retain singleton and pooled objects"
)
Check(ctx.state.visibleIcons[1] == firstIcon, "icons reused across toggle cycles")
local activeTickers = 0
for _, timer in ipairs(timers) do
    if timer.ticker and not timer.cancelled then
        activeTickers = activeTickers + 1
    end
end
Check(activeTickers == 1, "only one live feature ticker after repeated toggles")
if scenario == "legacy" then
    Check(fadeRegistrations == 22 and hostCallbacks ~= nil, "legacy fade and edit lifecycle restored on each enable")
    Plugin:AddSettings({}, {})
    hostSuppressed = true
    Plugin:UpdateVisibility()
    Check(Plugin._portalHidden and Plugin.frame.driver == "hide", "host profile suppression retains hidden driver")
    hostSuppressed = false
    Plugin:UpdateVisibility()
    hostCallbacks.Enter()
    Check(ctx.state.isEditModeActive and firstIcon:GetAttribute("type1") == nil, "legacy edit enters disarmed")
    hostCallbacks.Exit()
    FlushTimers()
    Boot.EnterEditMode()
    Check(hostEntry, "legacy entry routes through host gate")
else
    Boot.EnterEditMode()
    Check(ctx.state.isEditModeActive and firstIcon:GetAttribute("type1") == nil, "native edit enters disarmed")
    EditModeManagerFrame.active = false
    EventRegistry:TriggerEvent("EditMode.Exit")
    FlushTimers()
end
FlushTimers()
Check(firstIcon:GetAttribute("type1") == "spell", "edit exit restores action")
local paint = { iconSize = 32, maxVisible = 9, fadeAmount = 0 }
addon.PortalIcon.Configure(ctx, firstIcon, {
    type = "housing",
    category = "HOUSING",
    houseInfo = {
        neighborhoodGUID = "n",
        houseGUID = "h",
        plotID = 1,
    },
}, 0, paint)
Check(firstIcon:GetAttribute("type1") == "teleporthome", "complete housing action")
addon.PortalIcon.Configure(ctx, firstIcon, { type = "spell", spellID = 456, category = "CLASS" }, 0, paint)
Check(
    firstIcon:GetAttribute("house-guid") == nil and firstIcon:GetAttribute("spell") == 456,
    "pooled housing fields cleared"
)
addon.PortalIcon.Configure(ctx, firstIcon, { type = "housing", category = "HOUSING", houseInfo = {} }, 0, paint)
Check(
    firstIcon:GetAttribute("type1") == nil and firstIcon:GetAttribute("spell") == nil,
    "pending housing remains inert"
)
SetCombat(true)
Check(not Plugin.frame.shown, "native combat driver hides root")
addon.LibOrbitUI.Config.CommitValue(OrbitPortalSettings.spec, control, false)
Check(not Plugin._portalActive and Plugin.frame:GetAlpha() == 0, "combat disable releases product immediately")
SetCombat(false)
Check(Plugin.frame.driver == "hide" and not Plugin.frame.shown, "deferred hide completes after combat")
addon.LibOrbitUI.Config.CommitValue(OrbitPortalSettings.spec, control, true)
FlushTimers()
Check(
    Plugin._portalActive and Plugin.frame.shown and frameCreations == 1,
    "post-combat enable reuses frame: "
        .. tostring(Plugin._portalActive)
        .. ":"
        .. tostring(Plugin.frame.shown)
        .. ":"
        .. tostring(Plugin.frame.driver)
        .. ":"
        .. tostring(Plugin._portalHidden)
)
Check(#errors == 0, errors[1])
