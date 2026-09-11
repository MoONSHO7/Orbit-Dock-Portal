local scenario = ...
addon, frames, timers, errors, messages, eventCallbacks = {}, {}, {}, {}, {}, {}
combat, encounter, now, mapRequests, frameCreations, fadeRegistrations = false, false, 10, 0, 0, 0
table.freeze = function(value)
    return value
end
function CopyTable(source)
    local result = {}
    for key, value in pairs(source) do
        result[key] = type(value) == "table" and CopyTable(value) or value
    end
    return result
end
function wipe(value)
    for key in pairs(value) do
        value[key] = nil
    end
    return value
end
function Mixin(target, source)
    for key, value in pairs(source) do
        target[key] = value
    end
    return target
end
function issecretvalue(value)
    return value == "SECRET"
end
function InCombatLockdown()
    return combat
end
function GetPhysicalScreenSize()
    return 1920, 1080
end
function CreateColor(r, g, b, a)
    return {
        r = r,
        g = g,
        b = b,
        a = a,
        GetRGB = function(self)
            return self.r, self.g, self.b
        end,
    }
end
NORMAL_FONT_COLOR = CreateColor(1, 0.82, 0)
function GetScreenWidth()
    return 1365
end
function GetScreenHeight()
    return 768
end
function GetLocale()
    return "enUS"
end
function GetCursorPosition()
    return 0, 0
end
function GetMouseFoci()
    return {}
end
function GetCurrentKeyBoardFocus()
    return nil
end
function IsShiftKeyDown()
    return false
end
function GetTime()
    return now
end
function UnitClass()
    return "Mage", "MAGE"
end
function UnitFactionGroup()
    return "Alliance"
end
function UnitHasVehicleUI()
    return false
end
function PlaySoundFile() end
function print(message)
    messages[#messages + 1] = message
end
function geterrorhandler()
    return function(err)
        errors[#errors + 1] = err
    end
end
STANDARD_TEXT_FONT = "FixtureFont"
SlashCmdList, UISpecialFrames = {}, {}
C_InstanceEncounter = {
    IsEncounterInProgress = function()
        return encounter
    end,
}
C_PetBattles = {
    IsInBattle = function()
        return false
    end,
}
C_MythicPlus = {
    RequestMapInfo = function()
        mapRequests = mapRequests + 1
    end,
    RequestCurrentAffixes = function() end,
    GetSeasonBestAffixScoreInfoForMap = function()
        return {}, 123
    end,
    GetSeasonBestForMap = function()
        return { level = 10, durationSec = 1200 }
    end,
}
EventRegistry = {}
function EventRegistry:RegisterCallback(event, callback, owner)
    eventCallbacks[event] = eventCallbacks[event] or {}
    eventCallbacks[event][owner] = callback
end
function EventRegistry:UnregisterCallback(event, owner)
    if eventCallbacks[event] then
        eventCallbacks[event][owner] = nil
    end
end
function EventRegistry:TriggerEvent(event)
    for owner, callback in pairs(eventCallbacks[event] or {}) do
        callback(owner)
    end
end
C_Timer = {}
function C_Timer.NewTimer(delay, callback)
    local timer = { callback = callback, delay = delay }
    function timer:Cancel()
        self.cancelled = true
    end
    timers[#timers + 1] = timer
    return timer
end
function C_Timer.NewTicker(delay, callback)
    local timer = C_Timer.NewTimer(delay, callback)
    timer.ticker = true
    return timer
end
function FlushTimers()
    local count = #timers
    for i = 1, count do
        local timer = timers[i]
        if not timer.cancelled and not timer.ticker then
            timer.cancelled = true
            timer.callback()
        end
    end
    for _, frame in ipairs(frames) do
        if frame.shown and frame.scripts.OnUpdate then
            frame.scripts.OnUpdate(frame, 0.01)
        end
    end
    assert(#errors <= (allowedErrors or 0), errors[1])
end
function Emit(event, ...)
    for _, frame in ipairs(frames) do
        if frame.events[event] and frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame, event, ...)
        end
    end
    assert(#errors <= (allowedErrors or 0), errors[1])
end
local Frame = {}
function Frame:IsProtected()
    return self.protected
        or (self.kind ~= "Texture" and self.kind ~= "FontString" and self.parent and self.parent:IsProtected())
end
local function CheckProtected(frame)
    assert(not (combat and frame:IsProtected()), "protected mutation: " .. (frame.name or frame.kind))
end
function Frame:SetScript(name, callback)
    self.scripts[name] = callback
end
function Frame:GetScript(name)
    return self.scripts[name]
end
function Frame:HookScript(name, callback)
    local old = self.scripts[name]
    self.scripts[name] = function(...)
        if old then
            old(...)
        end
        callback(...)
    end
end
function Frame:RegisterEvent(event)
    self.events[event] = true
end
function Frame:UnregisterEvent(event)
    self.events[event] = nil
end
function Frame:UnregisterAllEvents()
    wipe(self.events)
end
function Frame:SetSize(width, height)
    CheckProtected(self)
    self.width, self.height = width, height
end
function Frame:SetWidth(width)
    CheckProtected(self)
    self.width = width
end
function Frame:SetHeight(height)
    CheckProtected(self)
    self.height = height
end
function Frame:GetSize()
    return self.width, self.height
end
function Frame:GetWidth()
    return self.width
end
function Frame:GetHeight()
    return self.height
end
function Frame:GetLeft()
    return self.left
end
function Frame:GetBottom()
    return self.bottom
end
function Frame:GetRight()
    return self.left + self.width
end
function Frame:GetTop()
    return self.bottom + self.height
end
function Frame:GetRect()
    return self.left, self.bottom, self.width, self.height
end
function Frame:GetCenter()
    return self.left + self.width / 2, self.bottom + self.height / 2
end
function Frame:GetEffectiveScale()
    return self.scale or 1
end
function Frame:SetScale(value)
    CheckProtected(self)
    self.scale = value
end
function Frame:GetParent()
    return self.parent
end
function Frame:SetParent(value)
    CheckProtected(self)
    self.parent = value
end
function Frame:ClearAllPoints()
    CheckProtected(self)
    self.point = nil
end
function Frame:SetPoint(point, relative, relativePoint, x, y)
    CheckProtected(self)
    self.point = { point, relative, relativePoint, x, y }
    self.left, self.bottom = x or 0, y or 0
end
function Frame:SetAllPoints(relative)
    CheckProtected(self)
    self.relative = relative
end
function Frame:GetNumPoints()
    return 1
end
function Frame:GetPoint()
    return unpack(self.point or { "CENTER", UIParent, "CENTER", 0, 0 })
end
function Frame:Show()
    CheckProtected(self)
    local changed = not self.shown
    self.shown = true
    if changed and self.scripts.OnShow then
        self.scripts.OnShow(self)
    end
end
function Frame:Hide()
    CheckProtected(self)
    local changed = self.shown
    self.shown = false
    if changed and self.scripts.OnHide then
        self.scripts.OnHide(self)
    end
end
function Frame:SetShown(shown)
    if shown then
        self:Show()
    else
        self:Hide()
    end
end
function Frame:IsShown()
    return self.shown
end
function Frame:IsVisible()
    return self.shown and (not self.parent or self.parent:IsVisible())
end
function Frame:SetAlpha(value)
    self.alpha = value
end
function Frame:GetAlpha()
    return self.alpha
end
function Frame:SetFrameLevel(value)
    self.level = value
end
function Frame:GetFrameLevel()
    return self.level
end
function Frame:SetAttribute(key, value)
    CheckProtected(self)
    self.attributes[key] = value
end
function Frame:GetAttribute(key)
    return self.attributes[key]
end
function Frame:EnableMouse(value)
    CheckProtected(self)
    self.mouse = value
end
function Frame:EnableKeyboard(value)
    assert(not combat)
    self.keyboard = value
end
function Frame:SetPropagateKeyboardInput(value)
    assert(not combat)
    self.propagate = value
end
function Frame:IsMouseOver()
    return false
end
function Frame:StartMoving()
    CheckProtected(self)
    self.moving = true
end
function Frame:StopMovingOrSizing()
    CheckProtected(self)
    self.moving = false
end
function Frame:ShowSelected()
    self.selected = true
    self:Show()
end
function Frame:ShowHighlighted()
    self.selected = false
    self:Show()
end
function Frame:SetText(value)
    self.textValue = value
end
function Frame:GetText()
    return self.textValue
end
function Frame:GetStringWidth()
    return #(self.textValue or "") * 6
end
function Frame:GetStringHeight()
    return 14
end
function Frame:SetColorTexture(...)
    self.color = { ... }
end
function Frame:SetGradient(...)
    self.gradient = { ... }
end
function Frame:SetHorizontalScroll(value)
    self.horizontalScroll = value
end
function Frame:GetHorizontalScroll()
    return self.horizontalScroll or 0
end
function Frame:GetHorizontalScrollRange()
    return 0
end
function Frame:SetFont(path, size, flags)
    self.font = { path, size, flags }
end
function Frame:GetFont()
    return unpack(self.font or { STANDARD_TEXT_FONT, 12, "" })
end
function Frame:SetFontObject(font)
    self.font = type(font) == "table" and font.font or nil
end
function Frame:GetFontString()
    if not self.fontString then
        self.fontString = self:CreateFontString()
    end
    return self.fontString
end
function Frame:GetObjectType()
    return self.kind
end
function Frame:IsObjectType(kind)
    return self.kind == kind
end
function Frame:GetRegions()
    return unpack(self.regions)
end
function Frame:CreateTexture()
    local region = CreateFrame("Texture", nil, self)
    self.regions[#self.regions + 1] = region
    return region
end
function Frame:CreateMaskTexture()
    local region = self:CreateTexture()
    region.kind = "MaskTexture"
    return region
end
function Frame:CreateFontString()
    local region = CreateFrame("FontString", nil, self)
    self.regions[#self.regions + 1] = region
    return region
end
function Frame:CreateAnimationGroup()
    return CreateFrame("AnimationGroup")
end
function Frame:CreateAnimation()
    return CreateFrame("Animation")
end
function Frame:Play()
    self.playing = true
end
function Frame:Stop()
    self.playing = false
end
function Frame:IsPlaying()
    return self.playing
end
function Frame:GetCheckedTexture()
    if not self.checkedTexture then
        self.checkedTexture = self:CreateTexture()
    end
    return self.checkedTexture
end
function Frame:SetChecked(value)
    self.checked = value
end
function Frame:GetChecked()
    return self.checked
end
function Frame:Enable()
    self.enabled = true
end
function Frame:Disable()
    self.enabled = false
end
function Frame:SetEnabled(value)
    self.enabled = value
end
function Frame:RegisterCallback(event, callback, owner)
    self.callbacks[owner] = callback
end
function Frame:UnregisterCallback(event, owner)
    self.callbacks[owner] = nil
end
function Frame:Init(value)
    self.value = value
    for owner, callback in pairs(self.callbacks) do
        callback(owner, value)
    end
end
function Frame:GetValue()
    return self.value
end
function Frame:GetVerticalScroll()
    return 0
end
function Frame:GetVerticalScrollRange()
    return 0
end
for _, name in ipairs({
    "SetClampedToScreen",
    "SetToplevel",
    "SetFrameStrata",
    "SetMovable",
    "SetClampRectInsets",
    "SetHitRectInsets",
    "RegisterForDrag",
    "RegisterForClicks",
    "EnableMouseWheel",
    "SetTexture",
    "SetVertexColor",
    "SetBlendMode",
    "AddMaskTexture",
    "SetAtlas",
    "SetTexCoord",
    "SetDesaturated",
    "SetHideCountdownNumbers",
    "SetDrawSwipe",
    "SetSwipeColor",
    "SetDrawEdge",
    "SetUseCircularEdge",
    "SetDrawBling",
    "SetCooldown",
    "Clear",
    "SetDuration",
    "SetOrder",
    "SetFromAlpha",
    "SetToAlpha",
    "SetStartDelay",
    "SetToFinalAlpha",
    "SetOffset",
    "SetTextColor",
    "SetJustifyH",
    "SetShadowOffset",
    "SetShadowColor",
    "SetSnapToPixelGrid",
    "SetTexelSnappingBias",
    "SetOwner",
    "AddLine",
    "AddDoubleLine",
    "SetScrollChild",
    "SetHideIfUnscrollable",
    "SetCheckedTexture",
    "SetVerticalScroll",
    "SetClipsChildren",
    "SetWordWrap",
    "SetNonSpaceWrap",
}) do
    Frame[name] = function() end
end
function Frame:SetAtlas(value)
    self.atlas = value
end
function Frame:SetJustifyH(value)
    self.justifyH = value
end
function Frame:GetJustifyH()
    return self.justifyH or "CENTER"
end
function CreateFrame(kind, name, parent, template)
    assert(not name or not _G[name], "duplicate named frame: " .. tostring(name))
    local frame = Mixin({
        kind = kind,
        name = name,
        parent = parent,
        template = template,
        width = 100,
        height = 100,
        left = 0,
        bottom = 0,
        level = 1,
        alpha = 1,
        shown = true,
        scripts = {},
        events = {},
        regions = {},
        attributes = {},
        callbacks = {},
        protected = template == "SecureActionButtonTemplate" or template == "SecureHandlerStateTemplate",
    }, Frame)
    frames[#frames + 1] = frame
    if name then
        _G[name] = frame
    end
    if name == "OrbitPortalFrame" then
        frameCreations = frameCreations + 1
    end
    if template == "ScrollFrameTemplate" then
        frame.ScrollBar = CreateFrame("Frame", nil, frame)
    end
    if template == "EditModeSystemSelectionTemplate" then
        parent.Selection = frame
    end
    if template == "EditModeSettingSliderTemplate" then
        frame.Label = frame:CreateFontString()
        frame.Slider = CreateFrame("Frame", nil, frame)
        frame.Slider.Slider = CreateFrame("Frame", nil, frame.Slider)
    end
    if template == "EditModeSettingCheckboxTemplate" then
        frame.Label = frame:CreateFontString()
        frame.Label:SetJustifyH("LEFT")
        frame.Button = CreateFrame("CheckButton", nil, frame)
    end
    return frame
end
function CreateFont(name)
    return CreateFrame("FontString", name)
end
function RunNextFrame(callback)
    C_Timer.NewTimer(0, callback)
end
function C_Timer.After(delay, callback)
    C_Timer.NewTimer(delay, callback)
end
function RegisterStateDriver(frame, attribute, condition)
    CheckProtected(frame)
    frame.driver = condition
    frame.shown = condition ~= "hide"
end
function SetCombat(value)
    combat = value
    if value then
        for _, frame in ipairs(frames) do
            if frame.driver then
                frame.shown = false
            end
        end
        Emit("PLAYER_REGEN_DISABLED")
    else
        Emit("PLAYER_REGEN_ENABLED")
    end
end
UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(1365, 768)
EditModeManagerFrame = CreateFrame("Frame", "EditModeManagerFrame")
function EditModeManagerFrame:IsEditModeActive()
    return self.active
end
function EditModeManagerFrame:IsEditModeLocked()
    return self.locked
end
function EditModeManagerFrame:CanEnterEditMode()
    return not combat and not encounter
end
function ShowUIPanel(frame)
    frame.active = true
    frame:Show()
    EventRegistry:TriggerEvent("EditMode.Enter")
end
function securecall(name, ...)
    return _G[name](...)
end
Settings = {
    RegisterCanvasLayoutCategory = function(panel, name)
        return { panel = panel, name = name }
    end,
    RegisterAddOnCategory = function(category)
        settingsCategory = category
    end,
}
if scenario == "disabled" then
    OrbitPortalDB = { version = 1, profiles = { default = { settings = { Enabled = false } } } }
elseif scenario == "blocked" then
    combat = true
elseif scenario == "future" then
    OrbitPortalDB = { version = 100, marker = "untouched" }
elseif scenario == "corrupt" then
    OrbitPortalDB =
        { version = 1, profiles = { default = { settings = { Position = "bad", MaxVisible = "bad", IconSize = 0 } } } }
end
if scenario == "legacy" then
    hostSettings, hostCallbacks, hostEnabled = {}, nil, true
    local Engine = {
        CanvasMode = { ComponentCatalog = { RegisterDeclared = function() end } },
        ComponentPlacement = {},
        FrameOrientation = {
            DetectOrientation = function()
                return "LEFT"
            end,
            RegisterCallback = function() end,
        },
        FramePersistence = { AttachSettingsListener = function() end, RestorePosition = function() end },
        PositionUtils = { ApplyTextPosition = function() end },
        OverrideUtils = { ApplyFontOverrides = function() end, ApplyOverrides = function() end },
        EditMode = {
            RegisterCallbacks = function(_, callbacks, owner, lifecycleOwner)
                hostCallbacks = callbacks
                assert(lifecycleOwner == addon.Portal)
            end,
            UnregisterCallbacks = function()
                hostCallbacks = nil
            end,
            TryEnter = function()
                hostEntry = true
            end,
        },
        SchemaBuilder = {
            SetTabRefreshCallback = function() end,
            AddSettingsTabs = function(_, schema, dialog, labels)
                return labels[1]
            end,
        },
        Config = {
            Render = function(_, dialog, frame, plugin, schema)
                assert(#schema.controls > 0)
            end,
        },
    }
    Orbit = {
        Engine = Engine,
        ExternalUIHost = { legacyPluginVersion = 1 },
        Skin = {
            SetFontWithShadow = function(_, region, path, size, flags)
                region:SetFont(path, size, flags)
            end,
        },
        OOCFadeMixin = {
            ApplyOOCFade = function()
                fadeRegistrations = fadeRegistrations + 1
            end,
        },
        OOCFadeService = {
            SetLifecycleHidden = function(_, frame, hidden)
                frame:SetAlpha(hidden and 0 or 1)
            end,
        },
        VisibilityEngine = {
            IsFrameMountedHidden = function()
                return false
            end,
        },
        GetTheme = function()
            return nil
        end,
        IsPluginEnabled = function()
            return hostEnabled
        end,
    }
    function Orbit:RegisterPlugin(name, system, options)
        local plugin = { name = name, system = system, defaults = options.defaults }
        function plugin:GetSetting(_, key)
            local value = hostSettings[key]
            return value ~= nil and value or CopyTable(self.defaults)[key]
        end
        function plugin:SetSetting(_, key, value)
            hostSettings[key] = value
        end
        function plugin:RegisterStandardEvents() end
        function plugin:RegisterVisibilityEvents() end
        function plugin:IsProfileSuppressed()
            return hostSuppressed
        end
        return plugin
    end
    function Orbit:LiveTogglePlugin(_, enabled)
        hostEnabled = enabled
        if enabled then
            addon.Portal:OnEnable()
        else
            addon.Portal:OnDisable()
        end
    end
elseif scenario == "oldhost" then
    Orbit = {
        Engine = {},
        RegisterPlugin = function()
            error("unmarked host must not register Portal")
        end,
    }
end
