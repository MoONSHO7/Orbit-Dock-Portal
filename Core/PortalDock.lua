
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
        Anchor = false,
        Position = { point = "LEFT", x = 8, y = 0 },
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

-- Static sort priority (favourites first); PortalData loads before this file, so build the map once instead of per RefreshDock.
local CAT_PRIORITY = {}
for i, cat in ipairs(addon.PortalData.CategoryOrder) do CAT_PRIORITY[cat] = i end

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
    -- Dock frame size (below) always uses the full-list maxVisible so the hover zone never collapses under the cursor while type-to-search filters the visible icons.
    maxVisible = Layout.NormalizeMaxVisible(maxVisible, totalItems)
    local compactness = Plugin:GetSetting(1, "Compactness") / 100
    local iconPoolIndex = 0

    -- Repaint-invariant reads resolved once here, threaded into every icon, so the loop runs no per-icon GetSetting / LibSharedMedia fetch / disabled-set alloc (hot path: scroll + type-to-search).
    local paint = {
        iconSize   = iconSize,
        maxVisible = maxVisible,
        fadeAmount = Layout.ResolveFadeAmount(Plugin:GetSetting(1, "FadeEffect")),
        fontPath   = Canvas.GetGlobalFontPath(),
        positions  = Plugin:GetSetting(1, "ComponentPositions") or {},
        disabled   = Canvas.BuildDisabledSet(Plugin),
    }

    -- One-shot flag set by the search filter engaging/clearing: fade the new icon set in instead of snapping.
    local animate = state.animatePaint
    state.animatePaint = nil

    -- Window with wraparound so the wheel cycles a short match set (a single match can't scroll); the full list always has >= maxVisible items, so it fills every slot.
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
    local dockThickness = iconSize + perpExtent + 2

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

    -- A rescan rebuilds portalList, so any type-to-search filter (which holds refs into the old list) is stale — drop it and render the fresh full list.
    state.searchFilter = nil

    local Scanner = addon.PortalScanner
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

    local orderIndex = {}
    for i, item in ipairs(state.portalList) do orderIndex[item] = i end
    table.sort(state.portalList, function(a, b)
        local pa = CAT_PRIORITY[a.displayGroup] or 999
        local pb = CAT_PRIORITY[b.displayGroup] or 999
        if pa ~= pb then return pa < pb end
        return orderIndex[a] < orderIndex[b]
    end)

    -- First-index map lets the shift+wheel up-branch find the prior-category boundary without an O(n^2) walk-back; search fields are lowercased once so type-to-search doesn't re-:lower() them.
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

-- Coalesce the PEW / ApplySettings / housing / SPELLS_CHANGED burst into one trailing scan; the combat check lives inside the callback so a lockdown starting mid-window defers instead of dropping it.
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

    local content = CreateFrame("Frame", nil, dock)
    content:SetAllPoints(dock)
    dock.content = content
    ctx.content = content

    -- Single hover-enter / hover-exit path shared by the dock, every icon, and the search-frame reconciler, so a missed OnLeave can't leave the dock revealed or the keyboard captured.
    local function HoverEnter()
        state.isMouseOver = true
        addon.PortalNavigation.ShowSearch()
        dock:SetAlpha(1)
        addon.PortalReveal.Reveal(ctx)
    end
    ctx.HoverEnter = HoverEnter

    local function HoverExit()
        if IsCursorOverDock() then return end
        state.isMouseOver = false
        addon.PortalNavigation.HideSearch()
        addon.PortalNavigation.ClearSearchBuffer()
        dock:SetAlpha(1)
        addon.PortalReveal.Conceal(ctx)
    end
    ctx.HoverExit = HoverExit

    addon.PortalNavigation.Install(ctx)

    dock:SetScript("OnEnter", HoverEnter)
    dock:SetScript("OnLeave", HoverExit)

    dock:SetAlpha(RESTING_ALPHA)
    dock.orbitAutoOrient = true

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

    -- Skip the paint while nothing is on cooldown (the common resting state), but still paint the tick a cooldown clears so desaturation lifts.
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
