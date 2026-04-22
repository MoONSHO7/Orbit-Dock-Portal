-- PortalNavigation.lua: Wheel scroll + type-to-search input for the dock.

local _, addon = ...

local ipairs = ipairs
local math_floor = math.floor
local GetTime = GetTime
local GetCursorPosition = GetCursorPosition
local IsShiftKeyDown = IsShiftKeyDown
local InCombatLockdown = InCombatLockdown

-- [ CONSTANTS ] -------------------------------------------------------------------------------------
local SEARCH_BUFFER_TIMEOUT = 1.0

-- [ MODULE ] ----------------------------------------------------------------------------------------
local Navigation = {}
addon.PortalNavigation = Navigation

local searchBuffer = ""
local searchBufferExpiry = 0
local searchFrame

-- Tiered matcher: exact-short > short-prefix > name-prefix > short-substring > name-substring.
local function ScoreMatch(data, needle)
    if not data then return 0 end
    local short = data.short and data.short:lower()
    local name  = data.name and data.name:lower()
    local inst  = data.instanceName and data.instanceName:lower()
    if short == needle then return 5 end
    if short and short:sub(1, #needle) == needle then return 4 end
    if (name and name:sub(1, #needle) == needle) or (inst and inst:sub(1, #needle) == needle) then return 3 end
    if short and short:find(needle, 1, true) then return 2 end
    if (name and name:find(needle, 1, true)) or (inst and inst:find(needle, 1, true)) then return 1 end
    return 0
end

local function FindBestMatchIndex(portalList, needle)
    local bestIndex, bestScore
    for i, data in ipairs(portalList) do
        local score = ScoreMatch(data, needle)
        if score > (bestScore or 0) then
            bestIndex, bestScore = i, score
            if score == 5 then break end
        end
    end
    return bestIndex
end

-- Returns a 0-based displayIndex (matches RefreshDock's slot loop), not a 1-based list index.
local function GetCursorDisplaySlot(visibleIcons)
    if #visibleIcons == 0 then return 0 end
    local cursorX, cursorY = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    cursorX, cursorY = cursorX / scale, cursorY / scale
    local bestSlot, bestDist = 0, nil
    for i, icon in ipairs(visibleIcons) do
        local ix, iy = icon:GetCenter()
        if ix and iy then
            local dx, dy = cursorX - ix, cursorY - iy
            local d2 = dx * dx + dy * dy
            if not bestDist or d2 < bestDist then
                bestSlot, bestDist = i - 1, d2
            end
        end
    end
    return bestSlot
end

function Navigation.Install(ctx)
    local dock = ctx.dock
    local state = ctx.state
    local Combat = addon.PortalCombat
    local NormalizeMaxVisible = addon.PortalLayout.NormalizeMaxVisible

    local function OnMouseWheel(_, delta)
        if not Combat.CanInteract() then return end
        local portalList = state.portalList
        local totalIcons = #portalList
        if totalIcons == 0 then return end

        if IsShiftKeyDown() then
            local maxVisible = NormalizeMaxVisible(ctx.plugin:GetSetting(1, "MaxVisible"), totalIcons)
            local centerSlot = math_floor(maxVisible / 2)
            local scrollOffset = state.scrollOffset
            local currentCenterIndex = ((scrollOffset + centerSlot) % totalIcons) + 1
            local currentCategory = portalList[currentCenterIndex] and portalList[currentCenterIndex].displayGroup

            if delta > 0 then
                for offset = 1, totalIcons - 1 do
                    local checkIndex = ((currentCenterIndex - 1 - offset) % totalIcons) + 1
                    local item = portalList[checkIndex]
                    if item and item.displayGroup ~= currentCategory then
                        local targetCategory = item.displayGroup
                        local firstOfCategory = checkIndex
                        for back = 1, totalIcons do
                            local prevIndex = ((checkIndex - 1 - back) % totalIcons) + 1
                            local prevItem = portalList[prevIndex]
                            if not prevItem or prevItem.displayGroup ~= targetCategory then
                                break
                            end
                            firstOfCategory = prevIndex
                        end
                        state.scrollOffset = (firstOfCategory - 1 - centerSlot + totalIcons) % totalIcons
                        break
                    end
                end
            else
                for offset = 1, totalIcons - 1 do
                    local checkIndex = ((currentCenterIndex - 1 + offset) % totalIcons) + 1
                    local item = portalList[checkIndex]
                    if item and item.displayGroup ~= currentCategory then
                        state.scrollOffset = (checkIndex - 1 - centerSlot + totalIcons) % totalIcons
                        break
                    end
                end
            end
        else
            state.scrollOffset = (state.scrollOffset - delta) % totalIcons
        end

        ctx.RefreshDock()
    end

    local function OnSearchChar(_, text)
        if not text or text == "" then return end
        if not state.isMouseOver or state.isEditModeActive then return end
        if GetCurrentKeyBoardFocus() then return end
        if not Combat.CanInteract() then return end

        local now = GetTime()
        if now > searchBufferExpiry then searchBuffer = "" end
        searchBuffer = searchBuffer .. text:lower()
        searchBufferExpiry = now + SEARCH_BUFFER_TIMEOUT

        local portalList = state.portalList
        local totalIcons = #portalList
        if totalIcons == 0 then return end

        local matchIndex = FindBestMatchIndex(portalList, searchBuffer)
        if not matchIndex then return end

        local targetSlot = GetCursorDisplaySlot(state.visibleIcons)
        state.scrollOffset = (matchIndex - 1 - targetSlot + totalIcons) % totalIcons
        ctx.RefreshDock()
    end

    dock:SetScript("OnMouseWheel", OnMouseWheel)

    -- Child of the dock so a combat dock:Hide() also hides this; Show/Hide is the only capture gate.
    -- Single-char keys are consumed so letter bindings (e.g. M = map) don't fire while searching;
    -- everything else propagates so ESC/Enter/bindings and any editbox input still work.
    searchFrame = CreateFrame("Frame", nil, dock)
    searchFrame:EnableKeyboard(true)
    if not InCombatLockdown() then
        searchFrame:SetPropagateKeyboardInput(true)
    end
    searchFrame:Hide()

    local function OnKey(self, key)
        if InCombatLockdown() then return end
        if GetCurrentKeyBoardFocus() or not (key and #key == 1) then
            self:SetPropagateKeyboardInput(true)
        else
            self:SetPropagateKeyboardInput(false)
        end
    end
    searchFrame:SetScript("OnKeyDown", OnKey)
    searchFrame:SetScript("OnKeyUp",   OnKey)
    searchFrame:SetScript("OnChar", OnSearchChar)
end

function Navigation.ShowSearch()
    if searchFrame then searchFrame:Show() end
end

function Navigation.HideSearch()
    if searchFrame then searchFrame:Hide() end
end

-- Re-seat propagation default after a /reload that happened under combat lockdown.
function Navigation.RestorePropagationDefault()
    if searchFrame and not InCombatLockdown() then
        searchFrame:SetPropagateKeyboardInput(true)
    end
end

function Navigation.ClearSearchBuffer()
    searchBuffer = ""
    searchBufferExpiry = 0
end
