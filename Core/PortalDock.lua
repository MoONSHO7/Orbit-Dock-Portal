-- PortalDock.lua: Plugin root — registration, shared ctx/state, dock frame, RefreshDock, lifecycle.

local _, addon = ...

---@type Orbit
local Orbit = Orbit
local OrbitEngine = Orbit.Engine

local math_max = math.max
local math_min = math.min
local ipairs = ipairs
local wipe = wipe
local InCombatLockdown = InCombatLockdown
local GetCursorPosition = GetCursorPosition

-- [ PLUGIN REGISTRATION ] ---------------------------------------------------------------------------
local SYSTEM_ID = "Orbit_Portal"

local Plugin = Orbit:RegisterPlugin("Portal Dock", SYSTEM_ID, {
    defaults = {
        IconSize = 32,
        Spacing = 5,
        MaxVisible = 9,
        HideLongCooldowns = true,
        FadeEffect = 0,
        Compactness = 0,
        Animation = 0,
        Favorites = {},
        ComponentPositions = {
            DungeonScore  = { anchorX = "CENTER", anchorY = "BOTTOM", offsetX = 0, offsetY = -2, justifyH = "CENTER" },
            DungeonShort  = { anchorX = "CENTER", anchorY = "TOP",    offsetX = 0, offsetY = 2,  justifyH = "CENTER" },
            FavouriteStar = { anchorX = "RIGHT",  anchorY = "TOP",    offsetX = 1, offsetY = 1,  justifyH = "RIGHT"  },
            Timer         = { anchorX = "CENTER", anchorY = "CENTER", offsetX = 0, offsetY = 0,  justifyH = "CENTER" },
        },
        DisabledComponents = { "DungeonShort", "Status" },
    },
})

Plugin.canvasMode = true
addon.PortalDock = Plugin

-- [ CONSTANTS ] -------------------------------------------------------------------------------------
local RESTING_ALPHA            = 1.0

local INITIAL_DOCK_WIDTH       = 44
local INITIAL_DOCK_HEIGHT      = 200
local INITIAL_DOCK_X_OFFSET    = 10
local HOVER_HIT_INSET          = 10
local DOCK_FRAME_LEVEL         = 100
local DOCK_FRAME_STRATA        = "MEDIUM"
local INITIAL_SCAN_DELAY       = 2
local EDIT_MODE_HIGHLIGHT_OUTSET = 5

local LONG_COOLDOWN_THRESHOLD  = 1800
local CLAMP_VISIBLE_MARGIN     = 30
-- Cheap (one C_Spell/C_Container call per existing item; no SpellBook re-scan); set-change events drive the full ScanAll path.
local COOLDOWN_REFRESH_INTERVAL = 15

local ICON_TEXCOORD_MIN        = 0.08
local ICON_TEXCOORD_MAX        = 0.92
local ICON_BORDER_SCALE        = 1.1
local CIRCULAR_MASK_PATH       = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local QUESTIONMARK_ICON        = "Interface\\Icons\\INV_Misc_QuestionMark"
local STAR_SIZE                = 12
local STAR_ATLAS               = "transmog-icon-favorite"
local BORDER_ATLAS_SEASONAL    = "talents-node-choiceflyout-circle-red"
local BORDER_ATLAS_DEFAULT     = "talents-node-choiceflyout-circle-gray"

-- [ STATE ] -----------------------------------------------------------------------------------------
local dock
local iconPool
local currentOrientation = "LEFT"

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
addon.PortalDockContext = ctx

-- [ ORIENTATION ] -----------------------------------------------------------------------------------
local function IsHorizontal()
    return currentOrientation == "TOP" or currentOrientation == "BOTTOM"
end

-- CENTER-anchored so scale expands symmetrically; axis inset by iconSize/2 from the dock edge.
local function PositionIconForOrientation(icon, dockFrame, arcOffset, centerPos, iconSize)
    icon:ClearAllPoints()
    local halfIcon = iconSize / 2
    local scale = icon:GetEffectiveScale()
    local w, h = icon:GetSize()
    if currentOrientation == "LEFT" then
        local x, y = OrbitEngine.Pixel:SnapPosition(halfIcon + arcOffset, -centerPos, "CENTER", w, h, scale)
        icon:SetPoint("CENTER", dockFrame, "TOPLEFT", x, y)
    elseif currentOrientation == "RIGHT" then
        local x, y = OrbitEngine.Pixel:SnapPosition(-halfIcon - arcOffset, -centerPos, "CENTER", w, h, scale)
        icon:SetPoint("CENTER", dockFrame, "TOPRIGHT", x, y)
    elseif currentOrientation == "TOP" then
        local x, y = OrbitEngine.Pixel:SnapPosition(centerPos, -halfIcon - arcOffset, "CENTER", w, h, scale)
        icon:SetPoint("CENTER", dockFrame, "TOPLEFT", x, y)
    else
        local x, y = OrbitEngine.Pixel:SnapPosition(centerPos, halfIcon + arcOffset, "CENTER", w, h, scale)
        icon:SetPoint("CENTER", dockFrame, "BOTTOMLEFT", x, y)
    end
end

-- [ REFRESH ORCHESTRATION ] -------------------------------------------------------------------------
-- Scan/filter/sort (heavy; set-change only) is split from icon paint (cheap; scroll + search) so navigation handlers re-position from state.portalList without ScanAll's hundreds of API calls.
local function RepaintIcons()
    local Combat = addon.PortalCombat
    if not dock or not Combat.CanInteract() then return end

    local Layout = addon.PortalLayout
    local IconModule = addon.PortalIcon
    local Canvas = addon.PortalCanvas
    local Favorites = addon.PortalFavorites

    for _, icon in ipairs(state.visibleIcons) do
        icon:Hide()
        icon:ClearAllPoints()
    end
    wipe(state.visibleIcons)

    local totalItems = state.portalList and #state.portalList or 0
    if totalItems == 0 then
        dock:Hide()
        return
    end

    local iconSize = Plugin:GetSetting(1, "IconSize")
    local spacing = Plugin:GetSetting(1, "Spacing")
    local maxVisible = Plugin:GetSetting(1, "MaxVisible")

    currentOrientation = OrbitEngine.FrameOrientation:DetectOrientation(dock)
    maxVisible = Layout.NormalizeMaxVisible(maxVisible, totalItems)
    local compactness = Plugin:GetSetting(1, "Compactness") / 100
    local iconPoolIndex = 0

    for displayIndex = 0, maxVisible - 1 do
        iconPoolIndex = iconPoolIndex + 1

        local actualIndex = ((state.scrollOffset + displayIndex) % totalItems) + 1
        local data = state.portalList[actualIndex]

        if data then
            if not iconPool then iconPool = {} end
            local icon = iconPool[iconPoolIndex]
            if not icon then
                icon = IconModule.Create(ctx)
                table.insert(iconPool, icon)
            end

            IconModule.Configure(ctx, icon, data, displayIndex)
            Canvas.ApplyIconComponents(Plugin, icon, data, state.mythicPlusCache, Favorites.IsFavorite(Plugin, data))

            local axialPos, arcOffset = Layout.CalculatePosition(displayIndex, maxVisible, iconSize, spacing, compactness)
            icon.stableCenterPos = axialPos
            PositionIconForOrientation(icon, dock.content, arcOffset, axialPos, iconSize)

            table.insert(state.visibleIcons, icon)
        end
    end

    local dockLength = math_max(Layout.CalculateAxialExtent(maxVisible, iconSize, spacing, compactness), iconSize)
    local perpExtent = Layout.CalculatePerpExtent(maxVisible, iconSize, spacing, compactness)
    local dockThickness = iconSize + perpExtent + 2

    if IsHorizontal() then
        dock:SetWidth(dockLength)
        dock:SetHeight(dockThickness)
    else
        dock:SetWidth(dockThickness)
        dock:SetHeight(dockLength)
    end

    -- Semi-clamp: drag past the edge but keep CLAMP_VISIBLE_MARGIN on-screen.
    local marginX = math_max(0, dock:GetWidth() - CLAMP_VISIBLE_MARGIN)
    local marginY = math_max(0, dock:GetHeight() - CLAMP_VISIBLE_MARGIN)
    dock:SetClampRectInsets(marginX, -marginX, -marginY, marginY)

    dock:Show()
    addon.PortalReveal.OnRepaint(ctx)
end

local function RefreshDock()
    local Combat = addon.PortalCombat
    if not dock or not Combat.CanInteract() then return end

    local Scanner = addon.PortalScanner
    local PD = addon.PortalData
    local Favorites = addon.PortalFavorites

    local rawList = Scanner:GetOrderedList()

    -- displayGroup pins favourites without clobbering item.category (still drives seasonal ring colour + M+ rendering).
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

    local catPriority = {}
    for i, cat in ipairs(PD.CategoryOrder) do catPriority[cat] = i end
    local orderIndex = {}
    for i, item in ipairs(state.portalList) do orderIndex[item] = i end
    table.sort(state.portalList, function(a, b)
        local pa = catPriority[a.displayGroup] or 999
        local pb = catPriority[b.displayGroup] or 999
        if pa ~= pb then return pa < pb end
        return orderIndex[a] < orderIndex[b]
    end)

    -- O(n) displayGroup → first-index map lets PortalNavigation's shift+wheel up-branch lookup the prior-category boundary instead of O(n²) walk-back per notch.
    state.firstIndexOfCategory = {}
    for i, item in ipairs(state.portalList) do
        local cat = item.displayGroup
        if state.firstIndexOfCategory[cat] == nil then state.firstIndexOfCategory[cat] = i end
    end

    RepaintIcons()
end

local function RequestRefresh()
    if addon.PortalCombat.CanInteract() then
        RefreshDock()
    else
        state.pendingRefresh = true
    end
end

ctx.RefreshDock = RefreshDock
ctx.RepaintIcons = RepaintIcons
ctx.RequestRefresh = RequestRefresh

-- [ DOCK CREATION ] ---------------------------------------------------------------------------------
local function CreateDock()
    dock = CreateFrame("Frame", "OrbitPortalDock", UIParent)
    dock:SetSize(INITIAL_DOCK_WIDTH, INITIAL_DOCK_HEIGHT)
    dock:SetPoint("LEFT", UIParent, "LEFT", INITIAL_DOCK_X_OFFSET, 0)

    OrbitEngine.Pixel:Enforce(dock)

    dock:SetFrameStrata(DOCK_FRAME_STRATA)
    dock:SetFrameLevel(DOCK_FRAME_LEVEL)
    dock:SetClampedToScreen(true)
    -- Permissive insets until RefreshDock tightens them; otherwise RestorePosition snaps a saved off-screen position on-screen before we have real dimensions.
    local sw, sh = GetScreenWidth(), GetScreenHeight()
    dock:SetClampRectInsets(sw, -sw, -sh, sh)
    dock:EnableMouse(true)
    -- Enlarge the hover-summon zone past the visible dock so the cursor catches it sooner without resizing the frame (which would move the icons).
    dock:SetHitRectInsets(-HOVER_HIT_INSET, -HOVER_HIT_INSET, -HOVER_HIT_INSET, -HOVER_HIT_INSET)
    dock:SetMovable(true)
    dock:RegisterForDrag("LeftButton")

    ctx.dock = dock

    -- IsMouseOver ignores hit-rect insets, so re-expand the test rect by the same pad to keep reveal/conceal aligned with the enlarged trigger (offsets: top, bottom, left, right).
    local function IsCursorOverDock()
        return dock:IsMouseOver(HOVER_HIT_INSET, -HOVER_HIT_INSET, -HOVER_HIT_INSET, HOVER_HIT_INSET)
    end
    ctx.IsCursorOverDock = IsCursorOverDock

    -- Icons live on this child so the reveal animation can move/fade them while the dock stays the fixed hover zone.
    local content = CreateFrame("Frame", nil, dock)
    content:SetAllPoints(dock)
    dock.content = content
    ctx.content = content

    addon.PortalNavigation.Install(ctx)

    dock:SetScript("OnEnter", function(self)
        state.isMouseOver = true
        addon.PortalNavigation.ShowSearch()
        self:SetAlpha(1)
        addon.PortalReveal.Reveal(ctx)
    end)

    dock:SetScript("OnLeave", function(self)
        if not IsCursorOverDock() then
            state.isMouseOver = false
            addon.PortalNavigation.HideSearch()
            addon.PortalNavigation.ClearSearchBuffer()
            self:SetAlpha(1)
            addon.PortalReveal.Conceal(ctx)
        end
    end)

    dock:SetAlpha(RESTING_ALPHA)
    dock.orbitAutoOrient = true

    function dock:CreateCanvasPreview(options)
        options = options or {}
        local iconSize = Plugin:GetSetting(1, "IconSize")
        local iconTexture = QUESTIONMARK_ICON
        -- Prefer a seasonal dungeon icon so DungeonScore has real-looking content to render.
        for _, item in ipairs(state.portalList or {}) do
            if item.category == "SEASONAL_DUNGEON" and item.icon then
                iconTexture = item.icon
                break
            end
        end

        local preview = CreateFrame("Frame", nil, options.parent or UIParent)
        preview:SetSize(iconSize, iconSize)
        OrbitEngine.Pixel:Enforce(preview)
        preview.sourceFrame = self
        preview.sourceWidth = iconSize
        preview.sourceHeight = iconSize
        preview.borderInset = 0
        preview.previewScale = 1
        preview.components = {}
        preview.systemIndex = 1

        local mask = preview:CreateMaskTexture()
        mask:SetAllPoints()
        mask:SetTexture(CIRCULAR_MASK_PATH, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")

        local iconTex = preview:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints()
        iconTex:SetTexCoord(ICON_TEXCOORD_MIN, ICON_TEXCOORD_MAX, ICON_TEXCOORD_MIN, ICON_TEXCOORD_MAX)
        iconTex:SetTexture(iconTexture)
        iconTex:AddMaskTexture(mask)

        local borderAtlas = iconTexture ~= QUESTIONMARK_ICON and BORDER_ATLAS_SEASONAL or BORDER_ATLAS_DEFAULT
        local borderTex = preview:CreateTexture(nil, "OVERLAY")
        borderTex:SetAtlas(borderAtlas, false)
        borderTex:SetPoint("CENTER")
        local previewScale = preview:GetEffectiveScale()
        local borderTexSize = OrbitEngine.Pixel:Snap(iconSize * ICON_BORDER_SCALE, previewScale)
        borderTex:SetSize(borderTexSize, borderTexSize)

        local savedPositions = Plugin:GetSetting(1, "ComponentPositions") or {}
        local fontPath = addon.PortalCanvas.GetGlobalFontPath()

        OrbitEngine.IconCanvasPreview:AttachTextComponents(preview, {
            { key = "Timer",        preview = "5",   anchorX = "CENTER", anchorY = "CENTER", offsetX = 0, offsetY = 0  },
            { key = "DungeonScore", preview = "285", anchorX = "CENTER", anchorY = "BOTTOM", offsetX = 0, offsetY = -2 },
            { key = "DungeonShort", preview = "AA",  anchorX = "CENTER", anchorY = "TOP",    offsetX = 0, offsetY = 2  },
        }, savedPositions, fontPath)

        local CreateDraggableComponent = OrbitEngine.CanvasMode and OrbitEngine.CanvasMode.CreateDraggableComponent
        if CreateDraggableComponent then
            local AnchorToCenter = OrbitEngine.PositionUtils.AnchorToCenter
            local halfW, halfH = preview.sourceWidth / 2, preview.sourceHeight / 2
            local srcStar = preview:CreateTexture(nil, "ARTWORK")
            srcStar:SetAtlas(STAR_ATLAS)
            srcStar:SetSize(STAR_SIZE, STAR_SIZE)
            srcStar:Hide()
            srcStar.orbitOriginalWidth, srcStar.orbitOriginalHeight = 12, 12

            local saved = savedPositions.FavouriteStar or {}
            local data = {
                anchorX = saved.anchorX or "RIGHT",
                anchorY = saved.anchorY or "TOP",
                offsetX = saved.offsetX or 1,
                offsetY = saved.offsetY or 1,
                justifyH = saved.justifyH or "RIGHT",
                overrides = saved.overrides,
            }
            local startX, startY = saved.posX, saved.posY
            if startX == nil or startY == nil then
                local cx, cy = AnchorToCenter(data.anchorX, data.anchorY, data.offsetX, data.offsetY, halfW, halfH)
                startX = startX or cx
                startY = startY or cy
            end
            local comp = CreateDraggableComponent(preview, "FavouriteStar", srcStar, startX, startY, data)
            if comp then
                comp:SetFrameLevel(preview:GetFrameLevel() + Orbit.Constants.Levels.Overlay)
                preview.components.FavouriteStar = comp
            end
        end

        return preview
    end

    return dock
end

-- [ LIFECYCLE ] -------------------------------------------------------------------------------------
function Plugin:OnLoad()
    dock = CreateDock()
    self.frame = dock

    Orbit.OOCFadeMixin:ApplyOOCFade(dock, self, 1)

    -- Prime M+ data so the first seasonal-dungeon tooltip has score/best-run without opening the M+ panel.
    C_MythicPlus.RequestMapInfo()
    C_MythicPlus.RequestCurrentAffixes()

    dock.editModeName = "Portal Dock"
    dock.systemIndex = 1
    dock.orbitNoSnap = true
    dock.orbitSelectionOutset = EDIT_MODE_HIGHLIGHT_OUTSET

    OrbitEngine.Frame:AttachSettingsListener(dock, self, 1)

    -- Orientation flips swap width/height, so re-anchor to keep the dock under the cursor mid-drag.
    OrbitEngine.Frame:RegisterOrientationCallback(dock, function(orientation)
        if currentOrientation == orientation then return end

        local cursorX, cursorY = GetCursorPosition()
        local scale = dock:GetEffectiveScale()
        cursorX, cursorY = cursorX / scale, cursorY / scale
        local dockCenterX = dock:GetLeft() + (dock:GetWidth() / 2)
        local dockCenterY = dock:GetBottom() + (dock:GetHeight() / 2)
        local offsetX = cursorX - dockCenterX
        local offsetY = cursorY - dockCenterY

        currentOrientation = orientation
        RefreshDock()

        if dock.orbitIsDragging then
            local newCenterX = cursorX - offsetX
            local newCenterY = cursorY - offsetY
            local newLeft = newCenterX - (dock:GetWidth() / 2)
            local newBottom = newCenterY - (dock:GetHeight() / 2)
            local dw, dh = dock:GetSize()
            newLeft, newBottom = OrbitEngine.Pixel:SnapPosition(newLeft, newBottom, "BOTTOMLEFT", dw, dh, dock:GetEffectiveScale())
            dock:ClearAllPoints()
            dock:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", newLeft, newBottom)
        end
    end)

    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        dock:SetMovable(true)
        OrbitEngine.FrameSelection:UpdateVisuals(dock)
    end

    OrbitEngine.Frame:RestorePosition(dock, self, 1)

    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.eventFrame:RegisterEvent("ENCOUNTER_START")
    self.eventFrame:RegisterEvent("ENCOUNTER_END")
    self.eventFrame:RegisterEvent("PLAYER_LOGIN")
    self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.eventFrame:RegisterEvent("SPELLS_CHANGED")
    self.eventFrame:RegisterEvent("PLAYER_HOUSE_LIST_UPDATED")

    self.eventFrame:SetScript("OnEvent", function(_, event, ...)
        local Scanner = addon.PortalScanner
        local Combat = addon.PortalCombat
        if event == "PLAYER_REGEN_ENABLED" then
            Combat.UpdateState(ctx)
            if state.pendingRefresh then
                state.pendingRefresh = false
                RefreshDock()
            else
                -- RefreshDock re-seats the reveal via RepaintIcons; with no pending refresh, re-seat any tween stranded when combat hid the dock.
                addon.PortalReveal.OnRepaint(ctx)
            end
        elseif event == "PLAYER_REGEN_DISABLED" then
            Combat.UpdateState(ctx)
        elseif event == "ENCOUNTER_START" then
            Combat.UpdateState(ctx)
        elseif event == "ENCOUNTER_END" then
            if not InCombatLockdown() then
                Combat.UpdateState(ctx)
                if state.pendingRefresh then
                    state.pendingRefresh = false
                    RefreshDock()
                else
                    addon.PortalReveal.OnRepaint(ctx)
                end
            else
                state.pendingRefresh = true
            end
        elseif event == "PLAYER_LOGIN" then
            -- Spell APIs return empty at the PLAYER_LOGIN instant; a small delay avoids a blank first scan.
            C_Timer.After(INITIAL_SCAN_DELAY, function()
                Scanner:RequestHousingData()
                RequestRefresh()
            end)
        elseif event == "SPELLS_CHANGED" then
            RequestRefresh()
        elseif event == "PLAYER_ENTERING_WORLD" then
            Scanner:RequestHousingData()
            RequestRefresh()
        elseif event == "PLAYER_HOUSE_LIST_UPDATED" then
            local houseInfos = ...
            Scanner:UpdateHousingCache(houseInfos)
            RequestRefresh()
        end
    end)

    self:RegisterStandardEvents()
    self:RegisterVisibilityEvents()

    if EventRegistry then
        EventRegistry:RegisterCallback("EditMode.Enter", function()
            state.isEditModeActive = true
            RequestRefresh()
        end, self)

        EventRegistry:RegisterCallback("EditMode.Exit", function()
            state.isEditModeActive = false
            RequestRefresh()
        end, self)
    end

    RequestRefresh()
    addon.PortalReveal.Install(ctx)

    -- Keep swirls live without ScanAll: RefreshCooldowns mutates state.portalList in place, then RepaintIcons feeds Cooldown:SetCooldown (C-sink, secret-safe).
    self._cooldownTicker = C_Timer.NewTicker(COOLDOWN_REFRESH_INTERVAL, function()
        if not dock or not addon.PortalCombat.CanInteract() then return end
        local list = state.portalList
        if not list or #list == 0 then return end
        addon.PortalScanner:RefreshCooldowns(list)
        RepaintIcons()
    end)
end

function Plugin:OnDisable()
    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
        self.eventFrame:SetScript("OnEvent", nil)
    end
    if EventRegistry then
        EventRegistry:UnregisterCallback("EditMode.Enter", self)
        EventRegistry:UnregisterCallback("EditMode.Exit", self)
    end
    if self._cooldownTicker then
        self._cooldownTicker:Cancel()
        self._cooldownTicker = nil
    end
end

function Plugin:UpdateVisibility()
    if not dock then return end
    local shouldHide = (C_PetBattles and C_PetBattles.IsInBattle()) or (UnitHasVehicleUI and UnitHasVehicleUI("player"))
        or (Orbit.MountedVisibility and Orbit.MountedVisibility:ShouldHide())
    dock:SetAlpha(shouldHide and 0 or RESTING_ALPHA)
end

function Plugin:ApplySettings()
    if not dock then return end
    RequestRefresh()
    addon.PortalReveal.Apply(ctx)
end

function Plugin:AddSettings(dialog, systemFrame)
    addon.PortalSchema.Build(self, dialog, systemFrame, ctx)
end

function Plugin:HandleCommand(cmd)
    addon.PortalCommands.Handle(ctx, cmd)
end
