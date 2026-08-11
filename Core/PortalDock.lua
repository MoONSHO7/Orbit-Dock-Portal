
local _, addon = ...

---@type Orbit
local Orbit = Orbit
local OrbitEngine = Orbit.Engine

local math_max = math.max
local math_min = math.min
local math_floor = math.floor
local ipairs = ipairs
local wipe = wipe
local InCombatLockdown = InCombatLockdown
local GetCursorPosition = GetCursorPosition

-- [ PLUGIN REGISTRATION ] ---------------------------------------------------------------------------------------------
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
        Anchor = false,
        Position = { point = "LEFT", x = 8, y = 0 },
        ComponentPositions = {
            DungeonScore  = { anchorX = "CENTER", anchorY = "BOTTOM", offsetX = 0, offsetY = -2, justifyH = "CENTER" },
            DungeonShort  = { anchorX = "CENTER", anchorY = "TOP",    offsetX = 0, offsetY = 2,  justifyH = "CENTER" },
            FavouriteStar = { anchorX = "RIGHT",  anchorY = "TOP",    offsetX = 1, offsetY = 1,  justifyH = "RIGHT"  },
            Timer         = { anchorX = "CENTER", anchorY = "CENTER", offsetX = 0, offsetY = 0,  justifyH = "CENTER" },
        },
        DisabledComponents = { "DungeonShort" },
    },
})

Plugin.canvasMode = true
addon.PortalDock = Plugin
OrbitEngine.CanvasMode.ComponentCatalog:RegisterDeclared("DungeonScore")
OrbitEngine.CanvasMode.ComponentCatalog:RegisterDeclared("DungeonShort")
OrbitEngine.CanvasMode.ComponentCatalog:RegisterDeclared("FavouriteStar")
OrbitEngine.CanvasMode.ComponentCatalog:RegisterDeclared("Timer")

-- [ CONSTANTS ] -------------------------------------------------------------------------------------------------------
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
local DOCK_THICKNESS_PAD       = 2
local COOLDOWN_REFRESH_INTERVAL = 15
local REFRESH_DEBOUNCE          = 0.1

local ICON_TEXCOORD_MIN        = 0.08
local ICON_TEXCOORD_MAX        = 0.92
local ICON_BORDER_SCALE        = 1.1
local CIRCULAR_MASK_PATH       = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local QUESTIONMARK_ICON        = "Interface\\Icons\\INV_Misc_QuestionMark"
local STAR_SIZE                = 12
local STAR_ATLAS               = "transmog-icon-favorite"
local BORDER_ATLAS_SEASONAL    = "talents-node-choiceflyout-circle-red"
local BORDER_ATLAS_DEFAULT     = "talents-node-choiceflyout-circle-gray"

-- [ STATE ] -----------------------------------------------------------------------------------------------------------
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

local CAT_PRIORITY = {}
for i, cat in ipairs(addon.PortalData.CategoryOrder) do CAT_PRIORITY[cat] = i end

-- [ ORIENTATION ] -----------------------------------------------------------------------------------------------------
local function IsHorizontal()
    return currentOrientation == "TOP" or currentOrientation == "BOTTOM"
end

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

-- [ REFRESH ORCHESTRATION ] -------------------------------------------------------------------------------------------
local function RepaintIcons()
    local Combat = addon.PortalCombat
    if not dock or not Combat.CanInteract() then return end

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
        dock:Hide()
        return
    end

    local authoredIconSize = Plugin:GetSetting(1, "IconSize")
    local authoredSpacing = Plugin:GetSetting(1, "Spacing")
    local maxVisible = Plugin:GetSetting(1, "MaxVisible")
    local dockScale = dock:GetEffectiveScale()
    local iconSize = OrbitEngine.Pixel:Snap(authoredIconSize, dockScale)
    local spacing = authoredSpacing == 0 and 0 or OrbitEngine.Pixel:Multiple(authoredSpacing, dockScale)

    currentOrientation = OrbitEngine.FrameOrientation:DetectOrientation(dock)
    maxVisible = Layout.NormalizeMaxVisible(maxVisible, totalItems)
    local compactness = Plugin:GetSetting(1, "Compactness") / 100
    local iconPoolIndex = 0

    local paint = {
        iconSize   = iconSize,
        maxVisible = maxVisible,
        fadeAmount = Layout.ResolveFadeAmount(Plugin:GetSetting(1, "FadeEffect")),
        fontPath   = Canvas.GetGlobalFontPath(),
        positions  = Plugin:GetSetting(1, "ComponentPositions") or {},
        disabled   = Canvas.BuildDisabledSet(Plugin),
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
            if not iconPool then iconPool = {} end
            local icon = iconPool[iconPoolIndex]
            if not icon then
                icon = IconModule.Create(ctx)
                table.insert(iconPool, icon)
            end

            IconModule.Configure(ctx, icon, data, displayIndex, paint)
            Canvas.ApplyIconComponents(icon, data, state.mythicPlusCache, data.displayGroup == "FAVORITE", paint)

            local axialPos, arcOffset = Layout.CalculatePosition(displayIndex, maxVisible, iconSize, spacing, compactness)
            icon.stableCenterPos = axialPos
            PositionIconForOrientation(icon, dock.content, arcOffset, axialPos, iconSize)

            if animate then IconModule.PlayAppear(icon) end
            table.insert(state.visibleIcons, icon)
        end
    end

    local dockLength = math_max(Layout.CalculateAxialExtent(maxVisible, iconSize, spacing, compactness), iconSize)
    local perpExtent = Layout.CalculatePerpExtent(maxVisible, iconSize, spacing, compactness)
    local dockThickness = iconSize + perpExtent + OrbitEngine.Pixel:Multiple(DOCK_THICKNESS_PAD, dockScale)

    if IsHorizontal() then
        dock:SetWidth(dockLength)
        dock:SetHeight(dockThickness)
    else
        dock:SetWidth(dockThickness)
        dock:SetHeight(dockLength)
    end

    local marginX = math_max(0, dock:GetWidth() - CLAMP_VISIBLE_MARGIN)
    local marginY = math_max(0, dock:GetHeight() - CLAMP_VISIBLE_MARGIN)
    dock:SetClampRectInsets(marginX, -marginX, -marginY, marginY)

    dock:Show()
    addon.PortalReveal.OnRepaint(ctx)
end

local function RefreshDock()
    local Combat = addon.PortalCombat
    if not dock or not Combat.CanInteract() then return end

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
    for i, item in ipairs(state.portalList) do orderIndex[item] = i end
    table.sort(state.portalList, function(a, b)
        local pa = CAT_PRIORITY[a.displayGroup] or 999
        local pb = CAT_PRIORITY[b.displayGroup] or 999
        if pa ~= pb then return pa < pb end
        return orderIndex[a] < orderIndex[b]
    end)

    local categoryNames = addon.PortalData.CategoryNames
    state.firstIndexOfCategory = {}
    for i, item in ipairs(state.portalList) do
        local cat = item.displayGroup
        if state.firstIndexOfCategory[cat] == nil then state.firstIndexOfCategory[cat] = i end
        item.searchShort = item.short and item.short:lower() or nil
        item.searchName  = item.name and item.name:lower() or nil
        item.searchInst  = item.instanceName and item.instanceName:lower() or nil
        local catName = categoryNames[item.category]
        item.searchCategory = catName and catName:lower() or nil
    end

    RepaintIcons()
end

local function RequestRefresh()
    Orbit.Async:Debounce("OrbitPortal_Refresh", function()
        if addon.PortalCombat.CanInteract() then
            RefreshDock()
        else
            state.pendingRefresh = true
        end
    end, REFRESH_DEBOUNCE)
end

ctx.RefreshDock = RefreshDock
ctx.RepaintIcons = RepaintIcons
ctx.RequestRefresh = RequestRefresh

-- [ DOCK CREATION ] ---------------------------------------------------------------------------------------------------
local function CreateDock()
    dock = CreateFrame("Frame", "OrbitPortalDock", UIParent)
    dock:SetSize(INITIAL_DOCK_WIDTH, INITIAL_DOCK_HEIGHT)
    dock:SetPoint("LEFT", UIParent, "LEFT", INITIAL_DOCK_X_OFFSET, 0)

    OrbitEngine.Pixel:Enforce(dock)

    dock:SetFrameStrata(DOCK_FRAME_STRATA)
    dock:SetFrameLevel(DOCK_FRAME_LEVEL)
    dock:SetClampedToScreen(true)
    local sw, sh = GetScreenWidth(), GetScreenHeight()
    dock:SetClampRectInsets(sw, -sw, -sh, sh)
    dock:EnableMouse(true)
    dock:SetHitRectInsets(-HOVER_HIT_INSET, -HOVER_HIT_INSET, -HOVER_HIT_INSET, -HOVER_HIT_INSET)
    dock:SetMovable(true)
    dock:RegisterForDrag("LeftButton")

    ctx.dock = dock

    -- IsMouseOver ignores hit-rect insets, so re-expand the test rect by the same pad to match the enlarged trigger.
    local function IsCursorOverDock()
        return dock:IsMouseOver(HOVER_HIT_INSET, -HOVER_HIT_INSET, -HOVER_HIT_INSET, HOVER_HIT_INSET)
    end
    ctx.IsCursorOverDock = IsCursorOverDock

    local content = CreateFrame("Frame", nil, dock)
    content:SetAllPoints(dock)
    dock.content = content
    ctx.content = content

    local function HoverEnter()
        state.isMouseOver = true
        addon.PortalNavigation.ShowSearch()
        addon.PortalReveal.Reveal(ctx)
    end
    ctx.HoverEnter = HoverEnter

    local function HoverExit()
        if IsCursorOverDock() then return end
        state.isMouseOver = false
        addon.PortalNavigation.HideSearch()
        addon.PortalNavigation.ClearSearchBuffer()
        addon.PortalReveal.Conceal(ctx)
    end
    ctx.HoverExit = HoverExit

    addon.PortalNavigation.Install(ctx)

    dock:SetScript("OnEnter", HoverEnter)
    dock:SetScript("OnLeave", HoverExit)

    dock:SetAlpha(RESTING_ALPHA)
    dock.orbitAutoOrient = true

    function dock:GetCanvasBorderInset()
        return 0
    end

    dock.orbitCanvasIconGrid = true
    function dock:CreateCanvasPreview(options)
        options = options or {}
        local iconSize = Plugin:GetSetting(1, "IconSize")
        local iconTexture = QUESTIONMARK_ICON
        for _, item in ipairs(state.portalList or {}) do
            if item.category == "SEASONAL_DUNGEON" and item.icon then
                iconTexture = item.icon
                break
            end
        end

        local parent = options.parent or UIParent
        local sourceScale = self:GetEffectiveScale()
        local snappedSize = OrbitEngine.Pixel:Snap(iconSize, sourceScale)
        local preview = options.reuse or CreateFrame("Frame", nil, parent)
        preview:SetParent(parent)
        preview:ClearAllPoints()
        preview:SetSize(snappedSize, snappedSize)
        preview.sourceFrame = self
        preview.sourceWidth = snappedSize
        preview.sourceHeight = snappedSize
        preview.borderInset = 0
        preview._sourceBorderSize = 0
        preview._sourceGeometryScale = sourceScale
        preview.previewScale = options.scale or 1
        preview.fixedSize = true
        preview.scalesTextWithSize = true
        preview.components = preview.components or {}
        wipe(preview.components)
        preview.systemIndex = options.systemIndex or 1

        if not preview._portalMask then
            preview._portalMask = preview:CreateMaskTexture()
            preview._portalMask:SetAllPoints()
            preview._portalMask:SetTexture(CIRCULAR_MASK_PATH, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")

            preview._portalIcon = preview:CreateTexture(nil, "ARTWORK")
            preview._portalIcon:SetAllPoints()
            preview._portalIcon:AddMaskTexture(preview._portalMask)

            preview._portalBorder = preview:CreateTexture(nil, "OVERLAY")
            preview._portalBorder:SetPoint("CENTER")

            preview._portalStarSource = preview:CreateTexture(nil, "ARTWORK")
            preview._portalStarSource:SetAtlas(STAR_ATLAS)
            preview._portalStarSource:SetSize(STAR_SIZE, STAR_SIZE)
            preview._portalStarSource:Hide()
            preview._portalStarSource.orbitOriginalWidth = STAR_SIZE
            preview._portalStarSource.orbitOriginalHeight = STAR_SIZE
        end

        local iconTex = preview._portalIcon
        iconTex:SetTexCoord(ICON_TEXCOORD_MIN, ICON_TEXCOORD_MAX, ICON_TEXCOORD_MIN, ICON_TEXCOORD_MAX)
        iconTex:SetVertexColor(1, 1, 1, 1)
        iconTex:SetAlpha(1)
        iconTex:SetDesaturated(false)
        iconTex:SetTexture(iconTexture)

        local borderAtlas = iconTexture ~= QUESTIONMARK_ICON and BORDER_ATLAS_SEASONAL or BORDER_ATLAS_DEFAULT
        local borderTex = preview._portalBorder
        borderTex:SetAtlas(borderAtlas, false)
        local borderTexSize = OrbitEngine.Pixel:Snap(iconSize * ICON_BORDER_SCALE, preview._sourceGeometryScale)
        borderTex:SetSize(borderTexSize, borderTexSize)
        preview.RefreshCanvasGeometry = function(current)
            local currentScale = self:GetEffectiveScale() or UIParent:GetEffectiveScale()
            local currentIconSize = Plugin:GetSetting(1, "IconSize")
            local currentSize = OrbitEngine.Pixel:Snap(currentIconSize, currentScale)
            current:SetSize(currentSize, currentSize)
            current.sourceWidth = currentSize
            current.sourceHeight = currentSize
            current._sourceGeometryScale = currentScale
            current._portalBorder:SetSize(
                OrbitEngine.Pixel:Snap(currentIconSize * ICON_BORDER_SCALE, currentScale),
                OrbitEngine.Pixel:Snap(currentIconSize * ICON_BORDER_SCALE, currentScale)
            )
            return currentSize, currentSize, currentScale
        end

        local savedPositions = Plugin:GetSetting(1, "ComponentPositions") or {}
        local fontPath = addon.PortalCanvas.GetGlobalFontPath()

        OrbitEngine.IconCanvasPreview:AttachTextComponents(preview, {
            { key = "Timer",        preview = "5",   anchorX = "CENTER", anchorY = "CENTER", offsetX = 0, offsetY = 0  },
            { key = "DungeonScore", preview = "285", anchorX = "CENTER", anchorY = "BOTTOM", offsetX = 0, offsetY = -2 },
            { key = "DungeonShort", preview = "AA",  anchorX = "CENTER", anchorY = "TOP",    offsetX = 0, offsetY = 2  },
        }, savedPositions, fontPath)

        local CreateDraggableComponent = OrbitEngine.CanvasMode and OrbitEngine.CanvasMode.CreateDraggableComponent
        if CreateDraggableComponent then
            local Placement = OrbitEngine.ComponentPlacement
            local halfW, halfH = preview.sourceWidth / 2, preview.sourceHeight / 2
            local srcStar = preview._portalStarSource

            local saved = savedPositions.FavouriteStar or {}
            local data = {
                anchorX = saved.anchorX or "RIGHT",
                anchorY = saved.anchorY or "TOP",
                offsetX = saved.offsetX or 1,
                offsetY = saved.offsetY or 1,
                justifyH = saved.justifyH or "RIGHT",
                overrides = saved.overrides,
            }
            for key, value in pairs(saved) do
                data[key] = value
            end
            local geometry = Placement:NewGeometry(
                halfW,
                halfH,
                halfW,
                halfH,
                STAR_SIZE,
                STAR_SIZE,
                Placement.BOX_OUTER,
                preview._sourceGeometryScale
            )
            data = Placement:NormalizeLegacy(data, geometry, Placement.POLICY_STANDARD, Placement.BOX_OUTER)
            local startX, startY = Placement:Decode(data, geometry, Placement.POLICY_STANDARD)
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

-- [ LIFECYCLE ] -------------------------------------------------------------------------------------------------------
function Plugin:OnLoad()
    dock = CreateDock()
    self.frame = dock

    Orbit.OOCFadeMixin:ApplyOOCFade(dock, self, 1)

    C_MythicPlus.RequestMapInfo()
    C_MythicPlus.RequestCurrentAffixes()

    dock.editModeName = "Portal Dock"
    dock.systemIndex = 1
    dock.orbitNoSnap = true
    dock.orbitSelectionOutset = EDIT_MODE_HIGHLIGHT_OUTSET

    OrbitEngine.FramePersistence:AttachSettingsListener(dock, self, 1)

    OrbitEngine.FrameOrientation:RegisterCallback(dock, function(orientation)
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

    OrbitEngine.FramePersistence:RestorePosition(dock, self, 1)

    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.eventFrame:RegisterEvent("ENCOUNTER_START")
    self.eventFrame:RegisterEvent("ENCOUNTER_END")
    self.eventFrame:RegisterEvent("PLAYER_LOGIN")
    self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.eventFrame:RegisterEvent("SPELLS_CHANGED")
    self.eventFrame:RegisterEvent("TOYS_UPDATED")
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
        elseif event == "SPELLS_CHANGED" or event == "TOYS_UPDATED" then
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

    local hadActiveCooldowns = false
    self._cooldownTicker = C_Timer.NewTicker(COOLDOWN_REFRESH_INTERVAL, function()
        if not dock or not addon.PortalCombat.CanInteract() then return end
        local list = state.portalList
        if not list or #list == 0 then return end
        addon.PortalScanner:RefreshCooldowns(list)
        local anyActive = false
        for _, item in ipairs(list) do
            if item.cooldown and item.cooldown > 0 then anyActive = true; break end
        end
        if anyActive or hadActiveCooldowns then RepaintIcons() end
        hadActiveCooldowns = anyActive
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
    local shouldHide = (C_PetBattles and C_PetBattles.IsInBattle())
        or (UnitHasVehicleUI and UnitHasVehicleUI("player"))
        or (Orbit.VisibilityEngine and Orbit.VisibilityEngine:IsFrameMountedHidden(self.name, 1))
        or false
    Orbit.OOCFadeService:SetLifecycleHidden(dock, shouldHide)
    dock:EnableMouse(not shouldHide)
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
