
local _, addon = ...
local Orbit = Orbit

local math_random = math.random
local pairs = pairs
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime

-- [ CONSTANTS ] -------------------------------------------------------------------------------------
local INITIAL_ICON_SIZE       = 36
local MISSING_ICON_FILE_ID    = 134400
local GCD_THRESHOLD           = 2
local APPEAR_DURATION         = 0.25

local ICON_TEXCOORD_MIN       = 0.08
local ICON_TEXCOORD_MAX       = 0.92
local ICON_BORDER_SCALE       = 1.1

local CIRCULAR_MASK_PATH      = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local STAR_SIZE               = 12
local STAR_SHADOW_SIZE        = 22
local STAR_SHADOW_ALPHA       = 0.95
local STAR_ATLAS              = "transmog-icon-favorite"
local STAR_SHADOW_ATLAS       = "PetJournal-BattleSlot-Shadow"

local BORDER_ATLAS_FAVOURITE  = "talents-node-choiceflyout-circle-yellow"
local BORDER_ATLAS_SEASONAL   = "talents-node-choiceflyout-circle-red"
local BORDER_ATLAS_DEFAULT    = "talents-node-choiceflyout-circle-gray"

local SHEEN_ATLAS             = "talents-sheen-node"
local SHEEN_WIDTH_SCALE       = 1.0
local SHEEN_SWEEP_DURATION    = 0.5
local SHEEN_FADEIN_DURATION   = 0.15
local SHEEN_FADEOUT_DURATION  = 0.20
local SHEEN_FADEOUT_START     = 0.30
local SHEEN_PEAK_ALPHA        = 0.85

local HIGHLIGHT_COLOR_R       = 1.0
local HIGHLIGHT_COLOR_G       = 0.95
local HIGHLIGHT_COLOR_B       = 0.70
local HIGHLIGHT_COLOR_A       = 0.35

local CLICK_SOUND_PATH        = "Interface\\AddOns\\Orbit_Portal\\Audio\\switch-sound.ogg"

-- [ MODULE ] ----------------------------------------------------------------------------------------
local Icon = {}
addon.PortalIcon = Icon

-- MaskTexture extends Texture but rejects AddMaskTexture with an error; per-region flag dedupes adds.
local function ApplyCircularMaskToCooldown(cooldown, mask)
    for _, region in pairs({cooldown:GetRegions()}) do
        if region:IsObjectType("Texture")
           and not region:IsObjectType("MaskTexture")
           and not region._orbitPortalMasked then
            region:AddMaskTexture(mask)
            region._orbitPortalMasked = true
        end
    end
end

function Icon.Create(ctx)
    local Favorites = addon.PortalFavorites
    local Tooltip = addon.PortalTooltip

    -- Parented to content (not dock) so the reveal animation carries the icons.
    local icon = CreateFrame("Button", nil, ctx.content, "SecureActionButtonTemplate")
    icon:RegisterForClicks("AnyUp", "AnyDown")
    icon:SetSize(INITIAL_ICON_SIZE, INITIAL_ICON_SIZE)
    Orbit.Engine.Pixel:Enforce(icon)

    -- The icon covers the dock's wheel zone; forward the wheel to the dock handler so scrolling over a result still scrolls/pages.
    icon:EnableMouseWheel(true)
    icon:SetScript("OnMouseWheel", function(self, delta)
        if ctx.HandleWheel then ctx.HandleWheel(self, delta) end
    end)

    icon.mask = icon:CreateMaskTexture()
    icon.mask:SetAllPoints()
    icon.mask:SetTexture(CIRCULAR_MASK_PATH, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")

    -- ARTWORK sublevel 7 puts the highlight above the icon texture but below the OVERLAY border.
    icon.highlight = icon:CreateTexture(nil, "ARTWORK", nil, 7)
    icon.highlight:SetAllPoints()
    icon.highlight:SetTexture("Interface\\Buttons\\WHITE8x8")
    icon.highlight:SetVertexColor(HIGHLIGHT_COLOR_R, HIGHLIGHT_COLOR_G, HIGHLIGHT_COLOR_B, HIGHLIGHT_COLOR_A)
    icon.highlight:SetBlendMode("ADD")
    icon.highlight:AddMaskTexture(icon.mask)
    icon.highlight:Hide()

    icon.sheen = icon:CreateTexture(nil, "ARTWORK", nil, 6)
    icon.sheen:SetAtlas(SHEEN_ATLAS)
    icon.sheen:SetBlendMode("ADD")
    icon.sheen:AddMaskTexture(icon.mask)
    icon.sheen:SetAlpha(0)

    icon.sheenAnim = icon.sheen:CreateAnimationGroup()
    icon.sheenTranslate = icon.sheenAnim:CreateAnimation("Translation")
    icon.sheenTranslate:SetDuration(SHEEN_SWEEP_DURATION)
    icon.sheenTranslate:SetOrder(1)
    icon.sheenFadeIn = icon.sheenAnim:CreateAnimation("Alpha")
    icon.sheenFadeIn:SetFromAlpha(0)
    icon.sheenFadeIn:SetToAlpha(SHEEN_PEAK_ALPHA)
    icon.sheenFadeIn:SetDuration(SHEEN_FADEIN_DURATION)
    icon.sheenFadeIn:SetOrder(1)
    icon.sheenFadeOut = icon.sheenAnim:CreateAnimation("Alpha")
    icon.sheenFadeOut:SetFromAlpha(SHEEN_PEAK_ALPHA)
    icon.sheenFadeOut:SetToAlpha(0)
    icon.sheenFadeOut:SetDuration(SHEEN_FADEOUT_DURATION)
    icon.sheenFadeOut:SetStartDelay(SHEEN_FADEOUT_START)
    icon.sheenFadeOut:SetOrder(1)

    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    icon.texture:SetTexCoord(ICON_TEXCOORD_MIN, ICON_TEXCOORD_MAX, ICON_TEXCOORD_MIN, ICON_TEXCOORD_MAX)
    icon.texture:AddMaskTexture(icon.mask)

    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints()
    icon.cooldown:SetHideCountdownNumbers(false)
    icon.cooldown:SetDrawSwipe(true)
    icon.cooldown:SetSwipeColor(0, 0, 0, 0.7)
    icon.cooldown:SetDrawEdge(true)
    icon.cooldown:SetUseCircularEdge(true)
    icon.cooldown:SetDrawBling(false)

    -- Dedicated mask so the cooldown swipe keeps a circular clip even if icon.mask is replaced.
    icon.cooldownMask = icon.cooldown:CreateMaskTexture()
    icon.cooldownMask:SetAllPoints(icon.cooldown)
    icon.cooldownMask:SetTexture(CIRCULAR_MASK_PATH, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")

    ApplyCircularMaskToCooldown(icon.cooldown, icon.cooldownMask)

    -- SetCooldown materialises new texture regions; re-apply the mask after each call.
    local originalSetCooldown = icon.cooldown.SetCooldown
    icon.cooldown.SetCooldown = function(self, start, duration, ...)
        originalSetCooldown(self, start, duration, ...)
        ApplyCircularMaskToCooldown(self, icon.cooldownMask)
    end

    local cooldownText = icon.cooldown:GetRegions()
    if cooldownText and cooldownText.SetFont then
        local font, size, flags = cooldownText:GetFont()
        if font and size then
            local baseSize = size * 0.7
            cooldownText:SetFont(font, baseSize, flags)
            icon.cooldownText = cooldownText
            icon.cooldownTextFont = font
            icon.cooldownTextBaseSize = baseSize
            icon.cooldownTextFlags = flags
        end
    end

    icon.FavouriteStarShadow = icon:CreateTexture(nil, "OVERLAY", nil, 5)
    icon.FavouriteStarShadow:SetAtlas(STAR_SHADOW_ATLAS)
    icon.FavouriteStarShadow:SetVertexColor(0, 0, 0, STAR_SHADOW_ALPHA)
    icon.FavouriteStarShadow:SetSize(STAR_SHADOW_SIZE, STAR_SHADOW_SIZE)
    icon.FavouriteStarShadow:Hide()

    icon.FavouriteStar = icon:CreateTexture(nil, "OVERLAY", nil, 7)
    icon.FavouriteStar:SetAtlas(STAR_ATLAS)
    icon.FavouriteStar:SetSize(STAR_SIZE, STAR_SIZE)
    icon.FavouriteStar:Hide()

    icon.DungeonScoreOverlay = CreateFrame("Frame", nil, icon)
    icon.DungeonScoreOverlay:SetAllPoints()
    icon.DungeonScoreOverlay:SetFrameLevel(icon:GetFrameLevel() + (Orbit.Constants.Levels and Orbit.Constants.Levels.IconOverlay or 5))
    icon.DungeonScore = icon.DungeonScoreOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    icon.DungeonScore:Hide()
    icon.DungeonShort = icon.DungeonScoreOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    icon.DungeonShort:Hide()

    icon.border = icon:CreateTexture(nil, "OVERLAY")
    icon.border:SetPoint("CENTER")

    -- Alpha only - SetScale is protected on secure buttons in combat. ToAlpha is set per play to the icon's fade-effect alpha so it lands exactly where a plain paint would.
    icon.appearAnim = icon:CreateAnimationGroup()
    icon.appearAnim:SetToFinalAlpha(true)
    icon.appearFade = icon.appearAnim:CreateAnimation("Alpha")
    icon.appearFade:SetFromAlpha(0)
    icon.appearFade:SetDuration(APPEAR_DURATION)

    -- Right-click toggles favourite (insecure); the cast lives on type1 (left only), so right-click never casts. Gate on `down` so the up-edge doesn't double-toggle.
    icon:SetScript("PreClick", function(self, button, down)
        if button == "RightButton" then
            if down then
                local data = self.portalData
                if data then
                    Favorites.Toggle(ctx.plugin, data)
                    ctx.RequestRefresh()
                end
            end
            return
        end
        if not down then return end
        -- Random hearthstone re-roll before the left-click cast: skip under lockdown — SetAttribute is protected, keep last pick.
        local data = self.portalData
        if data and data.type == "random_hearthstone" and data.availableHearthstones and not InCombatLockdown() then
            local available = data.availableHearthstones
            if #available > 0 then
                local chosen = available[math_random(1, #available)]
                if chosen.type == "toy" then
                    self:SetAttribute("type1", "toy")
                    self:SetAttribute("toy", chosen.itemID)
                    self:SetAttribute("item", nil)
                else
                    self:SetAttribute("type1", "item")
                    self:SetAttribute("item", chosen.name)
                    self:SetAttribute("toy", nil)
                end
            end
        end
    end)

    -- Cast fires on the up-edge for these buttons; play the flourish there (once, left-click only).
    icon:SetScript("PostClick", function(self, button, down)
        if button ~= "LeftButton" or down then return end
        PlaySoundFile(CLICK_SOUND_PATH, "SFX")
        if self.sheenAnim then self.sheenAnim:Stop(); self.sheenAnim:Play() end
    end)

    icon:SetScript("OnEnter", function(self)
        -- Slide carries icons outside the fixed dock zone; gate on the static (padded) summon zone, not the moving icon, or reveal fights conceal into a flicker.
        if not ctx.IsCursorOverDock() then return end
        if self.highlight then self.highlight:Show() end
        ctx.HoverEnter()
        if self.portalData then Tooltip.Show(ctx, self, self.portalData) end
    end)

    icon:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if self.highlight then self.highlight:Hide() end
        -- Mouse can exit the dock via an icon without dock:OnLeave firing, so release capture here (HoverExit re-checks the summon zone).
        ctx.HoverExit()
    end)

    return icon
end

function Icon.PlayAppear(icon)
    if not icon.appearAnim then return end
    icon.appearFade:SetToAlpha(icon.currentAlpha or 1)
    icon.appearAnim:Stop()
    icon.appearAnim:Play()
end

-- paint carries the repaint-invariant reads (iconSize, fadeAmount, normalized maxVisible) resolved once per pass, so nothing here re-reads settings per icon.
function Icon.Configure(ctx, icon, data, index, paint)
    local state = ctx.state
    local Layout = addon.PortalLayout

    icon.portalData = data
    icon.iconIndex = index
    icon.type = data.type

    local iconSize = paint.iconSize
    icon:SetSize(iconSize, iconSize)

    local iconScale = icon:GetEffectiveScale()
    local borderSize = Orbit.Engine.Pixel:Snap(iconSize * ICON_BORDER_SCALE, iconScale)

    local borderAtlas
    if data.displayGroup == "FAVORITE" then
        borderAtlas = BORDER_ATLAS_FAVOURITE
    elseif data.category == "SEASONAL_DUNGEON" or data.category == "SEASONAL_RAID" then
        borderAtlas = BORDER_ATLAS_SEASONAL
    else
        borderAtlas = BORDER_ATLAS_DEFAULT
    end
    icon.border:SetAtlas(borderAtlas, false)
    icon.border:SetSize(borderSize, borderSize)

    if icon.sheen then
        local sheenW = Orbit.Engine.Pixel:Snap(iconSize * SHEEN_WIDTH_SCALE, iconScale)
        icon.sheen:SetSize(sheenW, iconSize)
        icon.sheen:ClearAllPoints()
        icon.sheen:SetPoint("RIGHT", icon, "LEFT", 0, 0)
        if icon.sheenTranslate then
            icon.sheenTranslate:SetOffset(Orbit.Engine.Pixel:Snap(iconSize + sheenW, iconScale), 0)
        end
    end

    if data.iconAtlas then
        icon.texture:SetAtlas(data.iconAtlas)
    elseif data.icon then
        icon.texture:SetTexture(data.icon)
    else
        icon.texture:SetTexture(MISSING_ICON_FILE_ID)
    end

    if state.isEditModeActive then
        icon:SetAttribute("type1", nil)
        icon:SetAttribute("spell", nil)
        icon:SetAttribute("toy", nil)
        icon:SetAttribute("item", nil)
        icon:EnableMouse(false)
    else
        icon:EnableMouse(true)
        if data.type == "spell" then
            icon:SetAttribute("type1", "spell")
            icon:SetAttribute("spell", data.spellID)
        elseif data.type == "toy" then
            icon:SetAttribute("type1", "toy")
            icon:SetAttribute("toy", data.itemID)
        elseif data.type == "item" then
            icon:SetAttribute("type1", "item")
            icon:SetAttribute("item", data.name)
        elseif data.type == "random_hearthstone" then
            if data.availableHearthstones and #data.availableHearthstones > 0 then
                local chosen = data.availableHearthstones[math_random(1, #data.availableHearthstones)]
                if chosen.type == "toy" then
                    icon:SetAttribute("type1", "toy")
                    icon:SetAttribute("toy", chosen.itemID)
                else
                    icon:SetAttribute("type1", "item")
                    icon:SetAttribute("item", chosen.name)
                end
            end
        elseif data.type == "housing" then
            icon:SetAttribute("type1", "teleporthome")
            if data.houseInfo then
                icon:SetAttribute("house-neighborhood-guid", data.houseInfo.neighborhoodGUID)
                icon:SetAttribute("house-guid", data.houseInfo.houseGUID)
                icon:SetAttribute("house-plot-id", data.houseInfo.plotID)
            end
        end
    end

    if data.cooldown and data.cooldown > GCD_THRESHOLD then
        local duration = data.cooldownDuration or data.cooldown
        local elapsed = duration - data.cooldown
        local startTime = GetTime() - elapsed

        -- Re-apply after Clear() wipes the flags on recycled icons.
        icon.cooldown:SetDrawSwipe(false)
        icon.cooldown:SetDrawEdge(true)
        icon.cooldown:SetUseCircularEdge(true)
        icon.cooldown:SetDrawBling(false)
        icon.cooldown:SetCooldown(startTime, duration)
        icon.cooldown:Show()
        icon.texture:SetDesaturated(true)
    else
        icon.cooldown:Clear()
        icon.cooldown:Hide()
        icon.texture:SetDesaturated(false)
    end

    local targetAlpha
    if state.isEditModeActive then
        targetAlpha = 1
    else
        targetAlpha = Layout.FadeAlphaForIndex(index, paint.maxVisible, paint.fadeAmount)
    end
    icon.currentAlpha = targetAlpha
    icon:SetAlpha(targetAlpha)
    icon:Show()
end
