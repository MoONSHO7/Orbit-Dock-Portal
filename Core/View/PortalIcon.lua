-- PortalIcon.lua: Secure-action icon factory + per-data configure for the portal dock.

local _, addon = ...
local Orbit = Orbit

local math_random = math.random
local pairs = pairs
local InCombatLockdown = InCombatLockdown
local IsShiftKeyDown = IsShiftKeyDown
local GetTime = GetTime

-- [ CONSTANTS ] -------------------------------------------------------------------------------------
local INITIAL_ICON_SIZE       = 36
local MISSING_ICON_FILE_ID    = 134400
local GCD_THRESHOLD           = 2
local FADE_DEFAULT            = 20

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
    local dock = ctx.dock
    local state = ctx.state
    local Favorites = addon.PortalFavorites
    local Tooltip = addon.PortalTooltip

    local icon = CreateFrame("Button", nil, dock, "SecureActionButtonTemplate")
    icon:RegisterForClicks("AnyUp", "AnyDown")
    icon:SetSize(INITIAL_ICON_SIZE, INITIAL_ICON_SIZE)

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
    icon.DungeonScore = icon.DungeonScoreOverlay:CreateFontString(nil, "OVERLAY")
    icon.DungeonScore:Hide()
    icon.DungeonShort = icon.DungeonScoreOverlay:CreateFontString(nil, "OVERLAY")
    icon.DungeonShort:Hide()

    icon.border = icon:CreateTexture(nil, "OVERLAY")
    icon.border:SetPoint("CENTER")

    icon:SetScript("PreClick", function(self, button)
        if button == "RightButton" and IsShiftKeyDown() then
            local data = self.portalData
            if data then
                Favorites.Toggle(ctx.plugin, data)
                ctx.RequestRefresh()
            end
            return
        end
        -- Random hearthstone re-roll: skip under lockdown — SetAttribute is protected, keep last pick.
        local data = self.portalData
        if data and data.type == "random_hearthstone" and data.availableHearthstones and not InCombatLockdown() then
            local available = data.availableHearthstones
            if #available > 0 then
                local chosen = available[math_random(1, #available)]
                if chosen.type == "toy" then
                    self:SetAttribute("type", "toy")
                    self:SetAttribute("toy", chosen.itemID)
                    self:SetAttribute("item", nil)
                else
                    self:SetAttribute("type", "item")
                    self:SetAttribute("item", chosen.name)
                    self:SetAttribute("toy", nil)
                end
            end
        end
    end)

    icon:SetScript("PostClick", function(self)
        PlaySoundFile(CLICK_SOUND_PATH, "SFX")
        if self.sheenAnim then self.sheenAnim:Stop(); self.sheenAnim:Play() end
    end)

    icon:SetScript("OnEnter", function(self)
        if self.highlight then self.highlight:Show() end
        state.isMouseOver = true
        dock:SetAlpha(1)
        if self.portalData then Tooltip.Show(ctx, self, self.portalData) end
    end)

    icon:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if self.highlight then self.highlight:Hide() end
        -- Mouse can exit the dock via an icon without dock:OnLeave firing, so release capture here.
        if dock and not dock:IsMouseOver() then
            state.isMouseOver = false
            addon.PortalNavigation.HideSearch()
            dock:SetAlpha(1)
        end
    end)

    return icon
end

function Icon.Configure(ctx, icon, data, index)
    local plugin = ctx.plugin
    local state = ctx.state
    local Layout = addon.PortalLayout

    icon.portalData = data
    icon.iconIndex = index
    icon.type = data.type

    local iconSize = plugin:GetSetting(1, "IconSize")
    icon:SetSize(iconSize, iconSize)

    local borderSize = iconSize * ICON_BORDER_SCALE

    -- Border tiers: yellow=favourite, red=seasonal, grey=other.
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
        local sheenW = iconSize * SHEEN_WIDTH_SCALE
        icon.sheen:SetSize(sheenW, iconSize)
        icon.sheen:ClearAllPoints()
        icon.sheen:SetPoint("RIGHT", icon, "LEFT", 0, 0)
        if icon.sheenTranslate then
            icon.sheenTranslate:SetOffset(iconSize + sheenW, 0)
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
        icon:SetAttribute("type", nil)
        icon:SetAttribute("spell", nil)
        icon:SetAttribute("toy", nil)
        icon:SetAttribute("item", nil)
        icon:EnableMouse(false)
    else
        icon:EnableMouse(true)
        if data.type == "spell" then
            icon:SetAttribute("type", "spell")
            icon:SetAttribute("spell", data.spellID)
        elseif data.type == "toy" then
            icon:SetAttribute("type", "toy")
            icon:SetAttribute("toy", data.itemID)
        elseif data.type == "item" then
            icon:SetAttribute("type", "item")
            icon:SetAttribute("item", data.name)
        elseif data.type == "random_hearthstone" then
            if data.availableHearthstones and #data.availableHearthstones > 0 then
                local chosen = data.availableHearthstones[math_random(1, #data.availableHearthstones)]
                if chosen.type == "toy" then
                    icon:SetAttribute("type", "toy")
                    icon:SetAttribute("toy", chosen.itemID)
                else
                    icon:SetAttribute("type", "item")
                    icon:SetAttribute("item", chosen.name)
                end
            end
        elseif data.type == "housing" then
            icon:SetAttribute("type", "teleporthome")
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

    -- Edit mode forces alpha 1 so the layout stays visible while repositioning.
    local targetAlpha
    if state.isEditModeActive then
        targetAlpha = 1
    else
        local fadeAmount = plugin:GetSetting(1, "FadeEffect")
        -- Legacy boolean values: true = classic cosine (20), false/nil = off.
        if fadeAmount == true then fadeAmount = FADE_DEFAULT
        elseif fadeAmount == false then fadeAmount = 0 end
        local maxVisibleSetting = plugin:GetSetting(1, "MaxVisible")
        local normMaxVisible = Layout.NormalizeMaxVisible(maxVisibleSetting, #state.portalList)
        targetAlpha = Layout.EdgeAlphaForIndex(index, normMaxVisible, fadeAmount)
    end
    icon.currentAlpha = targetAlpha
    icon:SetAlpha(targetAlpha)
    icon:Show()
end
