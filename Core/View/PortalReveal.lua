local _, addon = ...
local Services = addon.PortalServices

local math_min = math.min
local math_max = math.max
local math_abs = math.abs
local InCombatLockdown = InCombatLockdown

-- [ CONSTANTS ] -------------------------------------------------------------------------------------------------------
local MODE_OFF = 0
local MODE_SLIDE = 1
local MODE_FADE = 2
local ANIM_DURATION = 0.18
local PROGRESS_EPSILON = 0.01

-- [ MODULE ] ----------------------------------------------------------------------------------------------------------
local Reveal = {}
addon.PortalReveal = Reveal

local content
local driver = CreateFrame("Frame", nil, UIParent)
driver:Hide()
local mode = MODE_OFF
local progress = 1
local target = 1
local hiddenOffsetX = 0
local hiddenOffsetY = 0

-- [ STATE ] -----------------------------------------------------------------------------------------------------------
local function ComputeHiddenOffset(ctx)
    local frame = ctx.frame
    local orientation = Services.DetectOrientation(frame)
    local w, h = frame:GetSize()
    if orientation == "LEFT" then
        hiddenOffsetX, hiddenOffsetY = -w, 0
    elseif orientation == "RIGHT" then
        hiddenOffsetX, hiddenOffsetY = w, 0
    elseif orientation == "TOP" then
        hiddenOffsetX, hiddenOffsetY = 0, h
    else
        hiddenOffsetX, hiddenOffsetY = 0, -h
    end
end

local function RestingTarget(ctx)
    if mode == MODE_OFF then
        return 1
    end
    if ctx.state.isEditModeActive then
        return 1
    end
    return ctx.state.isMouseOver and 1 or 0
end

local function ApplyProgress()
    local parent = content:GetParent()
    content:ClearAllPoints()
    if mode == MODE_SLIDE then
        local concealed = 1 - progress
        local ox, oy = hiddenOffsetX * concealed, hiddenOffsetY * concealed
        content:SetPoint("TOPLEFT", parent, "TOPLEFT", ox, oy)
        content:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", ox, oy)
        content:SetAlpha(progress)
    else
        content:SetAllPoints(parent)
        content:SetAlpha(mode == MODE_FADE and progress or 1)
    end
end

-- [ TWEEN DRIVER ] ----------------------------------------------------------------------------------------------------
local function UpdateTween(self, elapsed)
    -- content parents secure icons, so never move it under lockdown — stop and let OnRepaint re-assert post-combat.
    if InCombatLockdown() or not addon.PortalCombat.CanInteract() then
        self:Hide()
        return
    end
    local step = elapsed / ANIM_DURATION
    if progress < target then
        progress = math_min(target, progress + step)
    else
        progress = math_max(target, progress - step)
    end
    ApplyProgress()
    if math_abs(progress - target) < PROGRESS_EPSILON then
        progress = target
        ApplyProgress()
        self:Hide()
    end
end

local function StartTween(newTarget)
    if InCombatLockdown() then
        return
    end
    target = newTarget
    if math_abs(progress - target) < PROGRESS_EPSILON then
        progress = target
        ApplyProgress()
        driver:Hide()
        return
    end
    driver:Show()
end

-- [ PUBLIC ] ----------------------------------------------------------------------------------------------------------
function Reveal.Reveal(ctx)
    if mode == MODE_OFF then
        return
    end
    StartTween(1)
end

function Reveal.Conceal(ctx)
    if mode == MODE_OFF then
        return
    end
    StartTween(ctx.state.isEditModeActive and 1 or 0)
end

function Reveal.Apply(ctx)
    content = ctx.content
    mode = ctx.plugin:GetSetting(1, "Animation") or MODE_OFF
    driver:Hide()
    if InCombatLockdown() then
        return
    end
    ComputeHiddenOffset(ctx)
    progress = RestingTarget(ctx)
    target = progress
    ApplyProgress()
end

function Reveal.Install(ctx)
    content = ctx.content
    driver:SetScript("OnUpdate", UpdateTween)
    Reveal.Apply(ctx)
end

function Reveal.OnRepaint(ctx)
    if not content or InCombatLockdown() then
        return
    end
    ComputeHiddenOffset(ctx)
    if driver:IsShown() then
        return
    end
    progress = RestingTarget(ctx)
    target = progress
    ApplyProgress()
end

function Reveal.Stop()
    driver:Hide()
end
