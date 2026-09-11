local _, addon = ...

local Services = addon.PortalServices
local Pixel = Services.pixel
local Bridge = addon.PortalOrbit

local math_max = math.max
local math_min = math.min
local math_floor = math.floor
local ipairs = ipairs
local wipe = wipe
local InCombatLockdown = InCombatLockdown

-- [ PLUGIN REGISTRATION ] ---------------------------------------------------------------------------------------------
local SYSTEM_ID = "Orbit_Portal"

local Plugin
if Bridge then
    Plugin = Bridge.CreatePlugin()
else
    Plugin = {
        name = "Orbit-Portal",
        displayName = addon.L.PLU_VE_PORTAL,
        system = SYSTEM_ID,
        defaults = addon.PortalDefaults,
    }
    function Plugin:GetSetting(_, key)
        return addon.PortalStore:Get(key)
    end
    function Plugin:SetSetting(_, key, value)
        addon.PortalStore:Set(key, value)
    end
end
addon.Portal = Plugin

-- [ CONSTANTS ] -------------------------------------------------------------------------------------------------------
local RESTING_ALPHA = 1.0

local INITIAL_FRAME_WIDTH = 44
local INITIAL_FRAME_HEIGHT = 200
local INITIAL_FRAME_X_OFFSET = 10
local HOVER_HIT_INSET = 10
local FRAME_LEVEL = 100
local FRAME_STRATA = "MEDIUM"
local INITIAL_SCAN_DELAY = 2

local LONG_COOLDOWN_THRESHOLD = 1800
local CLAMP_VISIBLE_MARGIN = 30
local FRAME_THICKNESS_PAD = 2
local COOLDOWN_REFRESH_INTERVAL = 15
local REFRESH_DEBOUNCE = 0.1
local EVENTS = {
    "PLAYER_REGEN_ENABLED",
    "PLAYER_REGEN_DISABLED",
    "ENCOUNTER_START",
    "ENCOUNTER_END",
    "PLAYER_ENTERING_WORLD",
    "SPELLS_CHANGED",
    "TOYS_UPDATED",
    "PLAYER_HOUSE_LIST_UPDATED",
    "PET_BATTLE_OPENING_START",
    "PET_BATTLE_CLOSE",
    "UNIT_ENTERED_VEHICLE",
    "UNIT_EXITED_VEHICLE",
}
local VISIBILITY_DRIVER = "[combat][petbattle][vehicleui] hide; show"

-- [ STATE ] -----------------------------------------------------------------------------------------------------------
local frame
local iconPool
local currentOrientation = "LEFT"
local runtimeStartPending, refreshPending = false, false
local hadActiveCooldowns = false

-- Keep the native gameplay owner in Portal's load context before Orbit invokes the hosted lifecycle.
Plugin.eventFrame = CreateFrame("Frame")

local state = {
    portalList = {},
    visibleIcons = {},
    scrollOffset = 0,
    isMouseOver = false,
    isEditModeActive = false,
    pendingRefresh = false,
    mythicPlusCache = {},
}

local ctx = { plugin = Plugin, state = state }
addon.PortalContext = ctx

local CAT_PRIORITY = {}
for i, cat in ipairs(addon.PortalData.CategoryOrder) do
    CAT_PRIORITY[cat] = i
end

-- [ ORIENTATION ] -----------------------------------------------------------------------------------------------------
local function IsHorizontal()
    return currentOrientation == "TOP" or currentOrientation == "BOTTOM"
end

local function PositionIconForOrientation(icon, portalFrame, arcOffset, centerPos, iconSize)
    icon:ClearAllPoints()
    local halfIcon = iconSize / 2
    local scale = icon:GetEffectiveScale()
    local w, h = icon:GetSize()
    if currentOrientation == "LEFT" then
        local x, y = Pixel:SnapPosition(halfIcon + arcOffset, -centerPos, "CENTER", w, h, scale)
        icon:SetPoint("CENTER", portalFrame, "TOPLEFT", x, y)
    elseif currentOrientation == "RIGHT" then
        local x, y = Pixel:SnapPosition(-halfIcon - arcOffset, -centerPos, "CENTER", w, h, scale)
        icon:SetPoint("CENTER", portalFrame, "TOPRIGHT", x, y)
    elseif currentOrientation == "TOP" then
        local x, y = Pixel:SnapPosition(centerPos, -halfIcon - arcOffset, "CENTER", w, h, scale)
        icon:SetPoint("CENTER", portalFrame, "TOPLEFT", x, y)
    else
        local x, y = Pixel:SnapPosition(centerPos, halfIcon + arcOffset, "CENTER", w, h, scale)
        icon:SetPoint("CENTER", portalFrame, "BOTTOMLEFT", x, y)
    end
end

-- [ REFRESH ORCHESTRATION ] -------------------------------------------------------------------------------------------
local function RepaintIcons()
    local Combat = addon.PortalCombat
    if not frame or not Plugin._portalActive or not Combat.CanInteract() then
        return
    end

    local Layout = addon.PortalLayout
    local IconModule = addon.PortalIcon
    local Canvas = addon.PortalCanvas

    for _, icon in ipairs(state.visibleIcons) do
        icon:Hide()
        icon:ClearAllPoints()
    end
    wipe(state.visibleIcons)

    local totalItems = state.portalList and #state.portalList or 0
    if totalItems == 0 then
        frame:Hide()
        return
    end

    local authoredIconSize = Plugin:GetSetting(1, "IconSize")
    local authoredSpacing = Plugin:GetSetting(1, "Spacing")
    local maxVisible = Plugin:GetSetting(1, "MaxVisible")
    local frameScale = frame:GetEffectiveScale()
    local iconSize = Pixel:Snap(authoredIconSize, frameScale)
    local spacing = authoredSpacing == 0 and 0 or Pixel:Multiple(authoredSpacing, frameScale)

    currentOrientation = Services.DetectOrientation(frame)
    maxVisible = Layout.NormalizeMaxVisible(maxVisible, totalItems)
    local compactness = Plugin:GetSetting(1, "Compactness") / 100
    local iconPoolIndex = 0

    local paint = {
        iconSize = iconSize,
        maxVisible = maxVisible,
        fadeAmount = Layout.ResolveFadeAmount(Plugin:GetSetting(1, "FadeEffect")),
        fontPath = Canvas.GetGlobalFontPath(),
        positions = Plugin:GetSetting(1, "ComponentPositions") or {},
        disabled = Canvas.BuildDisabledSet(Plugin),
    }

    local animate = state.animatePaint
    state.animatePaint = nil

    local renderList = (state.searchFilter and #state.searchFilter > 0) and state.searchFilter or state.portalList
    local renderCount = #renderList
    local shown = math_min(renderCount, maxVisible)
    local startSlot = math_floor((maxVisible - shown) / 2)
    local windowStart = state.scrollOffset % renderCount

    for k = 0, shown - 1 do
        iconPoolIndex = iconPoolIndex + 1

        local displayIndex = startSlot + k
        local actualIndex = ((windowStart + k) % renderCount) + 1
        local data = renderList[actualIndex]

        if data then
            if not iconPool then
                iconPool = {}
            end
            local icon = iconPool[iconPoolIndex]
            if not icon then
                icon = IconModule.Create(ctx)
                table.insert(iconPool, icon)
            end

            IconModule.Configure(ctx, icon, data, displayIndex, paint)
            Canvas.ApplyIconComponents(icon, data, state.mythicPlusCache, data.displayGroup == "FAVORITE", paint)

            local axialPos, arcOffset =
                Layout.CalculatePosition(displayIndex, maxVisible, iconSize, spacing, compactness)
            icon.stableCenterPos = axialPos
            PositionIconForOrientation(icon, frame.content, arcOffset, axialPos, iconSize)

            if animate then
                IconModule.PlayAppear(icon)
            end
            table.insert(state.visibleIcons, icon)
        end
    end

    local frameLength = math_max(Layout.CalculateAxialExtent(maxVisible, iconSize, spacing, compactness), iconSize)
    local perpExtent = Layout.CalculatePerpExtent(maxVisible, iconSize, spacing, compactness)
    local frameThickness = iconSize + perpExtent + Pixel:Multiple(FRAME_THICKNESS_PAD, frameScale)

    if IsHorizontal() then
        frame:SetWidth(frameLength)
        frame:SetHeight(frameThickness)
    else
        frame:SetWidth(frameThickness)
        frame:SetHeight(frameLength)
    end

    local marginX = math_max(0, frame:GetWidth() - CLAMP_VISIBLE_MARGIN)
    local marginY = math_max(0, frame:GetHeight() - CLAMP_VISIBLE_MARGIN)
    frame:SetClampRectInsets(marginX, -marginX, -marginY, marginY)

    if not Plugin._portalHidden then
        frame:Show()
    end
    addon.PortalReveal.OnRepaint(ctx)
end

local function Refresh()
    local Combat = addon.PortalCombat
    if not frame or not Plugin._portalActive or not Combat.CanInteract() then
        return
    end

    state.searchFilter = nil

    local Scanner = addon.PortalScanner
    local Favorites = addon.PortalFavorites

    local rawList = Scanner:GetOrderedList()

    for _, item in ipairs(rawList) do
        item.displayGroup = Favorites.IsFavorite(Plugin, item) and "FAVORITE" or item.category
    end

    local hideLongCooldowns = Plugin:GetSetting(1, "HideLongCooldowns")
    local enabledCategories = Plugin:GetSetting(1, "EnabledCategories") or {}
    state.portalList = {}
    for _, item in ipairs(rawList) do
        local cooldownRemaining = item.cooldown or 0
        local isCurrentSeason = item.category == "SEASONAL_DUNGEON" or item.category == "SEASONAL_RAID"
        local cooldownPass = not hideLongCooldowns or isCurrentSeason or cooldownRemaining < LONG_COOLDOWN_THRESHOLD
        local categoryPass = item.displayGroup == "FAVORITE" or enabledCategories[item.category] ~= false
        if cooldownPass and categoryPass then
            table.insert(state.portalList, item)
        end
    end

    local orderIndex = {}
    for i, item in ipairs(state.portalList) do
        orderIndex[item] = i
    end
    table.sort(state.portalList, function(a, b)
        local pa = CAT_PRIORITY[a.displayGroup] or 999
        local pb = CAT_PRIORITY[b.displayGroup] or 999
        if pa ~= pb then
            return pa < pb
        end
        return orderIndex[a] < orderIndex[b]
    end)

    local categoryNames = addon.PortalData.CategoryNames
    state.firstIndexOfCategory = {}
    for i, item in ipairs(state.portalList) do
        local cat = item.displayGroup
        if state.firstIndexOfCategory[cat] == nil then
            state.firstIndexOfCategory[cat] = i
        end
        item.searchShort = item.short and item.short:lower() or nil
        item.searchName = item.name and item.name:lower() or nil
        item.searchInst = item.instanceName and item.instanceName:lower() or nil
        local catName = categoryNames[item.category]
        item.searchCategory = catName and catName:lower() or nil
    end

    RepaintIcons()
end

local function RefreshWhenReady()
    if not Plugin._portalActive then
        return
    end
    if addon.PortalCombat.CanInteract() then
        Refresh()
    else
        state.pendingRefresh = true
    end
end

local function RefreshCooldowns()
    if not Plugin._portalActive or not addon.PortalCombat.CanInteract() then
        return
    end
    local list = state.portalList
    if #list == 0 then
        return
    end
    addon.PortalScanner:RefreshCooldowns(list)
    local anyActive = false
    for _, item in ipairs(list) do
        if item.cooldown and item.cooldown > 0 then
            anyActive = true
            break
        end
    end
    if anyActive or hadActiveCooldowns then
        RepaintIcons()
    end
    hadActiveCooldowns = anyActive
end

local RequestRefresh
local function StartRuntimeWork(frame)
    frame:SetScript("OnUpdate", nil)
    if not Plugin._portalActive then
        return
    end
    if refreshPending then
        refreshPending = false
        Services.runtime:Debounce("refresh", RefreshWhenReady, REFRESH_DEBOUNCE)
    end
    if runtimeStartPending then
        runtimeStartPending = false
        Services.runtime:After("initialScan", INITIAL_SCAN_DELAY, function()
            if not Plugin._portalActive then
                return
            end
            addon.PortalScanner:RequestHousingData()
            RequestRefresh()
        end)
        Services.runtime:Ticker("cooldowns", COOLDOWN_REFRESH_INTERVAL, RefreshCooldowns)
    end
end

RequestRefresh = function()
    if not Plugin._portalActive then
        return
    end
    Services.runtime:Cancel("refresh")
    refreshPending = true
    Plugin.eventFrame:SetScript("OnUpdate", StartRuntimeWork)
end

ctx.Refresh = Refresh
ctx.RepaintIcons = RepaintIcons
ctx.RequestRefresh = RequestRefresh

-- [ FRAME CREATION ] --------------------------------------------------------------------------------------------------
local function CreatePortalFrame()
    frame = CreateFrame("Frame", "OrbitPortalFrame", UIParent, "SecureHandlerStateTemplate")
    frame:Hide()
    frame:SetSize(INITIAL_FRAME_WIDTH, INITIAL_FRAME_HEIGHT)
    frame:SetPoint("LEFT", UIParent, "LEFT", INITIAL_FRAME_X_OFFSET, 0)

    Pixel:Enforce(frame)

    frame:SetFrameStrata(FRAME_STRATA)
    frame:SetFrameLevel(FRAME_LEVEL)
    frame:SetClampedToScreen(true)
    local sw, sh = GetScreenWidth(), GetScreenHeight()
    frame:SetClampRectInsets(sw, -sw, -sh, sh)
    frame:EnableMouse(true)
    frame:SetHitRectInsets(-HOVER_HIT_INSET, -HOVER_HIT_INSET, -HOVER_HIT_INSET, -HOVER_HIT_INSET)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    ctx.frame = frame

    -- IsMouseOver ignores hit-rect insets, so re-expand the test rect by the same pad to match the enlarged trigger.
    local function IsCursorOverFrame()
        return frame:IsMouseOver(HOVER_HIT_INSET, -HOVER_HIT_INSET, -HOVER_HIT_INSET, HOVER_HIT_INSET)
    end
    ctx.IsCursorOverFrame = IsCursorOverFrame

    local content = CreateFrame("Frame", nil, frame)
    content:SetAllPoints(frame)
    frame.content = content
    ctx.content = content

    local function HoverEnter()
        state.isMouseOver = true
        addon.PortalNavigation.ShowSearch()
        addon.PortalReveal.Reveal(ctx)
    end
    ctx.HoverEnter = HoverEnter

    local function HoverExit()
        if IsCursorOverFrame() then
            return
        end
        state.isMouseOver = false
        addon.PortalNavigation.HideSearch()
        addon.PortalNavigation.ClearSearchBuffer()
        addon.PortalReveal.Conceal(ctx)
    end
    ctx.HoverExit = HoverExit

    addon.PortalNavigation.Install(ctx)

    frame:SetScript("OnEnter", HoverEnter)
    frame:SetScript("OnLeave", HoverExit)

    frame:SetAlpha(RESTING_ALPHA)
    frame.orbitAutoOrient = true

    function frame:GetCanvasBorderInset()
        return 0
    end

    if Bridge then
        Bridge.AttachCanvas(ctx)
    end

    return frame
end

-- [ LIFECYCLE ] -------------------------------------------------------------------------------------------------------
function Plugin:OnLoad()
    frame = CreatePortalFrame()
    self.frame = frame
    self._portalConstructed = true
    frame.editModeName = addon.L.PLU_VE_PORTAL
    frame.systemIndex = 1
    C_MythicPlus.RequestMapInfo()
    C_MythicPlus.RequestCurrentAffixes()
    if Bridge then
        Bridge.AttachFrame(ctx)
    end
    addon.PortalReveal.Install(ctx)
    self.eventFrame:SetScript("OnEvent", function(_, event, ...)
        if not self._portalActive then
            return
        end
        local Combat = addon.PortalCombat
        if event == "PLAYER_HOUSE_LIST_UPDATED" then
            addon.PortalScanner:UpdateHousingCache(...)
        elseif event == "PLAYER_ENTERING_WORLD" then
            addon.PortalScanner:RequestHousingData()
        end
        if
            event == "PLAYER_REGEN_ENABLED"
            or event == "PLAYER_REGEN_DISABLED"
            or event == "ENCOUNTER_START"
            or event == "ENCOUNTER_END"
            or event == "PET_BATTLE_OPENING_START"
            or event == "PET_BATTLE_CLOSE"
            or event == "UNIT_ENTERED_VEHICLE"
            or event == "UNIT_EXITED_VEHICLE"
        then
            Combat.UpdateState(ctx)
        end
        RequestRefresh()
        self:UpdateVisibility()
    end)
end

local function ReconcileVisibility()
    if not frame then
        return
    end
    local shown = Plugin._portalActive and not Plugin._portalHidden
    RegisterStateDriver(frame, "visibility", shown and VISIBILITY_DRIVER or "hide")
    frame:EnableMouse(shown)
    if shown then
        if #state.portalList == 0 and not state.isEditModeActive then
            frame:Hide()
        end
    else
        frame:Hide()
    end
end
local visibilityHandle = Services.runtime:RegisterReconciler("visibility", ReconcileVisibility)

function Plugin:OnEnable()
    self._portalActive = true
    runtimeStartPending, hadActiveCooldowns = true, false
    for _, event in ipairs(EVENTS) do
        self.eventFrame:RegisterEvent(event)
    end
    if Bridge then
        Bridge.Enable(ctx)
    end
    self:UpdateVisibility()
    RequestRefresh()
end

function Plugin:OnDisable()
    self._portalActive = false
    self.eventFrame:SetScript("OnUpdate", nil)
    runtimeStartPending, refreshPending = false, false
    self.eventFrame:UnregisterAllEvents()
    Services.runtime:CancelAll()
    if Bridge then
        Bridge.Disable()
    end
    addon.PortalNavigation.HideSearch()
    addon.PortalNavigation.ClearSearchBuffer()
    addon.PortalReveal.Stop()
    state.isMouseOver, state.isEditModeActive = false, false
    state.pendingRefresh = false
    Services.tooltipHide()
    frame:SetAlpha(0)
    Services.runtime:Invalidate(visibilityHandle)
end

function Plugin:UpdateVisibility()
    if not frame then
        return
    end
    local hidden = not self._portalActive
        or (C_PetBattles and C_PetBattles.IsInBattle())
        or (UnitHasVehicleUI and UnitHasVehicleUI("player"))
        or not addon.PortalCombat.CanInteract()
    if Bridge then
        hidden = Bridge.UpdateVisibility(ctx, hidden)
    end
    self._portalHidden = hidden and true or false
    if not Bridge then
        frame:SetAlpha(hidden and 0 or RESTING_ALPHA)
    end
    Services.runtime:Invalidate(visibilityHandle)
end

function Plugin:ApplySettings()
    if not frame or not self._portalActive then
        return
    end
    addon.PortalNavigation.ApplySettings()
    RequestRefresh()
    addon.PortalReveal.Apply(ctx)
    self:UpdateVisibility()
end

function Plugin:AddSettings(dialog, systemFrame)
    Bridge.RenderSettings(self, dialog, systemFrame, ctx)
end

function Plugin:HandleCommand(cmd)
    addon.PortalCommands.Handle(ctx, cmd)
end
