-- PortalNavigation.lua: Wheel scroll + type-to-search input for the dock.

local _, addon = ...
local Orbit = Orbit

local ipairs = ipairs
local table_sort = table.sort
local math_floor = math.floor
local GetTime = GetTime
local GetCursorPosition = GetCursorPosition
local IsShiftKeyDown = IsShiftKeyDown
local InCombatLockdown = InCombatLockdown

-- [ CONSTANTS ] -------------------------------------------------------------------------------------
local SEARCH_BUFFER_TIMEOUT = 0.8    -- idle seconds before the typed query resets (matches the display hold)
local DISPLAY_HOLD          = 0.8    -- typed letters stay lit this long after the last keystroke
local DISPLAY_FADE          = 0.35   -- then fade out quickly, signalling "buffer cleared, listening for a new search"
local DISPLAY_FONT_SIZE     = 20
local DISPLAY_GAP           = 6
local DISPLAY_LEVEL_OFFSET  = 10
local DISPLAY_MATCH_COLOR   = { 1, 1, 1 }
local DISPLAY_NOMATCH_COLOR = { 1, 0.25, 0.25 }
local SCORE_EXACT_SHORT     = 5    -- top match tier: short-code exact hit
local HOVER_POLL_INTERVAL   = 0.1    -- self-correcting hover check; releases keys if OnLeave was missed mid-repaint

-- [ MODULE ] ----------------------------------------------------------------------------------------
local Navigation = {}
addon.PortalNavigation = Navigation

local searchBuffer = ""
local searchBufferExpiry = 0
local preFilterScroll = 0      -- browse scrollOffset saved when a filter engages, restored when it clears
local installedCtx             -- captured in Install so file-level helpers can reach state / RepaintIcons
local searchFrame
local searchDisplay
local searchDisplayText
local searchFadeAnim

-- [ SEARCH FILTER ] ---------------------------------------------------------------------------------
-- Drive the dock's filtered view: `items` = ranked matches to show (centred), or nil to restore the full list. RepaintIcons reads state.searchFilter; scrollOffset is saved on engage / restored on clear so browsing resumes where it left off.
local function ApplyFilter(items)
    if not installedCtx then return end
    local state = installedCtx.state
    if items and #items > 0 then
        if not state.searchFilter then preFilterScroll = state.scrollOffset; state.animatePaint = true end
        state.searchFilter = items
        state.scrollOffset = 0
    elseif state.searchFilter then
        state.searchFilter = nil
        state.scrollOffset = preFilterScroll
        state.animatePaint = true
    else
        return
    end
    if installedCtx.RepaintIcons then installedCtx.RepaintIcons() end
end

-- [ SEARCH DISPLAY ] --------------------------------------------------------------------------------
-- The typed query prints beside the dock, holds, then fades; the fade doubles as the "buffer reset, listening for a new search" cue.
local function ClearBufferAndDisplay()
    searchBuffer = ""
    searchBufferExpiry = 0
    ApplyFilter(nil)
    if not searchDisplay then return end
    -- IsPlaying guard so the anim's own OnFinished doesn't re-Stop itself; a live fade (mouse-leave) is stopped.
    if searchFadeAnim and searchFadeAnim:IsPlaying() then searchFadeAnim:Stop() end
    searchDisplay:SetAlpha(1)
    searchDisplay:Hide()
end

local function ShowSearchBufferText(hasMatch)
    if not searchDisplay then return end
    searchDisplayText:SetText(searchBuffer:upper())
    local c = hasMatch and DISPLAY_MATCH_COLOR or DISPLAY_NOMATCH_COLOR
    searchDisplayText:SetTextColor(c[1], c[2], c[3])
    if searchFadeAnim then searchFadeAnim:Stop() end
    searchDisplay:SetAlpha(1)
    searchDisplay:Show()
    if searchFadeAnim then searchFadeAnim:Play() end
end

-- Extend the reset timer and keep the readout lit — called on typing, TAB, and mouse movement over the dock, so the filtered results don't clear while the user reaches for them.
local function KeepSearchAlive()
    searchBufferExpiry = GetTime() + SEARCH_BUFFER_TIMEOUT
    if searchDisplay and searchDisplay:IsShown() and searchFadeAnim then
        searchFadeAnim:Stop()
        searchDisplay:SetAlpha(1)
        searchFadeAnim:Play()
    end
end

-- [ MATCHING ] --------------------------------------------------------------------------------------
-- Tiered matcher: prefix hits outrank substring hits, so a name/code that starts with the query wins over one that merely contains it; exact short-code wins outright. Category name is searched too (typing "Legion" surfaces the whole Legion Dungeons category plus any name containing it).
local function ScoreMatch(data, needle)
    if not data then return 0 end
    local short = data.searchShort
    local name  = data.searchName
    local inst  = data.searchInst
    local cat   = data.searchCategory
    if short == needle then return SCORE_EXACT_SHORT end
    if short and short:sub(1, #needle) == needle then return 4 end
    if (name and name:sub(1, #needle) == needle) or (inst and inst:sub(1, #needle) == needle)
        or (cat and cat:sub(1, #needle) == needle) then return 3 end
    if short and short:find(needle, 1, true) then return 2 end
    if (name and name:find(needle, 1, true)) or (inst and inst:find(needle, 1, true))
        or (cat and cat:find(needle, 1, true)) then return 1 end
    return 0
end

-- Ranked match list (best first) as item refs, for the current query; RepaintIcons renders these as the filtered dock.
local function RankMatches(portalList, needle)
    local entries = {}
    if needle and needle ~= "" then
        for i, data in ipairs(portalList) do
            local score = ScoreMatch(data, needle)
            if score > 0 then
                entries[#entries + 1] = { item = data, score = score, order = i }
            end
        end
        table_sort(entries, function(a, b)
            if a.score ~= b.score then return a.score > b.score end
            return a.order < b.order
        end)
    end
    local items = {}
    for k, e in ipairs(entries) do items[k] = e.item end
    return items
end

function Navigation.Install(ctx)
    installedCtx = ctx
    local dock = ctx.dock
    local state = ctx.state
    local Combat = addon.PortalCombat
    local NormalizeMaxVisible = addon.PortalLayout.NormalizeMaxVisible

    local function OnMouseWheel(_, delta)
        if not Combat.CanInteract() then return end
        -- While filtering, the wheel pages the results and keeps the query alive; category-jump doesn't apply to a filtered view.
        local filter = state.searchFilter
        if filter and #filter > 0 then
            KeepSearchAlive()
            state.scrollOffset = (state.scrollOffset - delta) % #filter
            ctx.RepaintIcons()
            return
        end
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
                -- Up-branch uses RefreshDock's precomputed firstIndexOfCategory — was O(n²) via nested walk-back.
                local firstIndexMap = state.firstIndexOfCategory
                for offset = 1, totalIcons - 1 do
                    local checkIndex = ((currentCenterIndex - 1 - offset) % totalIcons) + 1
                    local item = portalList[checkIndex]
                    if item and item.displayGroup ~= currentCategory then
                        local target = firstIndexMap and firstIndexMap[item.displayGroup] or checkIndex
                        state.scrollOffset = (target - 1 - centerSlot + totalIcons) % totalIcons
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

        ctx.RepaintIcons()
    end

    -- TAB pages the filtered results when there are more than fit, and keeps the query alive either way.
    local function PageResults()
        KeepSearchAlive()
        local filter = state.searchFilter
        if filter and #filter > 0 then
            state.scrollOffset = (state.scrollOffset + 1) % #filter
            ctx.RepaintIcons()
        end
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

        local matches = RankMatches(state.portalList, searchBuffer)
        local hasMatch = #matches > 0

        -- Filter the dock to the matches (or restore the full list on a miss); the readout goes red when nothing matches.
        ApplyFilter(hasMatch and matches or nil)
        ShowSearchBufferText(hasMatch)
    end

    dock:EnableMouseWheel(true)
    dock:SetScript("OnMouseWheel", OnMouseWheel)
    -- Icons are mouse-enabled children and swallow the wheel, so they forward it here (see Icon.Create) — otherwise scrolling over a result does nothing.
    ctx.HandleWheel = OnMouseWheel

    -- Child of dock so combat dock:Hide() hides this too; consumes single-char keys (letter bindings stay silent while searching) and propagates ESC/Enter/etc.
    searchFrame = CreateFrame("Frame", nil, dock)
    searchFrame:EnableKeyboard(true)
    if not InCombatLockdown() then
        searchFrame:SetPropagateKeyboardInput(true)
    end
    searchFrame:Hide()

    local function ApplyPropagation(self, key)
        if InCombatLockdown() then return end
        if GetCurrentKeyBoardFocus() or not (key and #key == 1) then
            self:SetPropagateKeyboardInput(true)
        else
            self:SetPropagateKeyboardInput(false)
        end
    end

    local function OnKeyDown(self, key)
        if InCombatLockdown() then return end
        -- TAB pages the filtered results while a query is live: consume it so it doesn't also target-swap. With no active query it falls through and TAB targets as usual.
        if key == "TAB" and searchBuffer ~= "" and state.isMouseOver and not state.isEditModeActive
           and not GetCurrentKeyBoardFocus() and Combat.CanInteract() then
            self:SetPropagateKeyboardInput(false)
            PageResults()
            return
        end
        ApplyPropagation(self, key)
    end

    searchFrame:SetScript("OnKeyDown", OnKeyDown)
    searchFrame:SetScript("OnKeyUp",   ApplyPropagation)
    searchFrame:SetScript("OnChar", OnSearchChar)

    -- RepaintIcons churns icons under a stationary cursor: an icon can be Hidden mid-hover so its OnLeave never lands, stranding this keyboard-capturing frame shown and eating every key. Poll the static summon zone while shown and release on exit; the frame is hidden (zero cost) whenever not hovering. While over the dock, cursor movement keeps a live query alive so the filtered results don't clear as the user reaches for them.
    searchFrame:SetScript("OnUpdate", function(self, elapsed)
        self.pollElapsed = (self.pollElapsed or 0) + elapsed
        if self.pollElapsed < HOVER_POLL_INTERVAL then return end
        self.pollElapsed = 0
        if not (ctx.IsCursorOverDock and ctx.IsCursorOverDock()) then
            if ctx.HoverExit then ctx.HoverExit() end
            return
        end
        if searchBuffer ~= "" then
            local x, y = GetCursorPosition()
            if x ~= self.lastCursorX or y ~= self.lastCursorY then
                self.lastCursorX, self.lastCursorY = x, y
                KeepSearchAlive()
            end
        end
    end)

    -- Typed-query readout at the dock's bottom-right — parented to the static dock (not content), so the reveal tween never drags it; the fade animation cues the buffer reset.
    local fontPath = addon.PortalCanvas.GetGlobalFontPath()
    searchDisplay = CreateFrame("Frame", nil, dock)
    searchDisplay:SetFrameLevel(dock:GetFrameLevel() + DISPLAY_LEVEL_OFFSET)
    searchDisplay:SetSize(1, 1)
    searchDisplay:SetPoint("BOTTOMLEFT", dock, "BOTTOMRIGHT", DISPLAY_GAP, 0)
    searchDisplay:Hide()

    searchDisplayText = searchDisplay:CreateFontString(nil, "OVERLAY")
    searchDisplayText:SetPoint("BOTTOMLEFT")
    Orbit.Skin:SetFontWithShadow(searchDisplayText, fontPath, DISPLAY_FONT_SIZE, "OUTLINE")
    searchDisplayText:SetTextColor(1, 1, 1)

    searchFadeAnim = searchDisplay:CreateAnimationGroup()
    searchFadeAnim:SetToFinalAlpha(true)
    local fade = searchFadeAnim:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetStartDelay(DISPLAY_HOLD)
    fade:SetDuration(DISPLAY_FADE)
    searchFadeAnim:SetScript("OnFinished", ClearBufferAndDisplay)
end

function Navigation.ShowSearch()
    if searchFrame then searchFrame:Show() end
end

function Navigation.HideSearch()
    if not searchFrame then return end
    -- Release the key capture before hiding so a lingering frame (or the next show) never eats keyboard input.
    if not InCombatLockdown() then searchFrame:SetPropagateKeyboardInput(true) end
    searchFrame:Hide()
end

-- Re-seat propagation default after a /reload that happened under combat lockdown.
function Navigation.RestorePropagationDefault()
    if searchFrame and not InCombatLockdown() then
        searchFrame:SetPropagateKeyboardInput(true)
    end
end

function Navigation.ClearSearchBuffer()
    ClearBufferAndDisplay()
end
