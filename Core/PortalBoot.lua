local addonName, addon = ...
local L = addon.L
local Services = addon.PortalServices
local UI = addon.LibOrbitUI
local Bridge = addon.PortalOrbit
local Plugin = addon.Portal
local ctx = addon.PortalContext
local Boot = {}
addon.PortalBoot = Boot

local loginReady, storeReady = false, false
local initializationFailed = false
local dialog, movement
local CATEGORY_BUTTON_WIDTH, CATEGORY_BUTTON_HEIGHT = 240, 30
local CATEGORY_PADDING = 20

local function ApplyPosition(_, position, reason)
    if reason then
        Plugin:SetSetting(1, "Position", position)
    end
    local frame = Plugin.frame
    frame:ClearAllPoints()
    local point = position.point or "LEFT"
    frame:SetPoint(point, UIParent, position.relativePoint or point, position.x or 0, position.y or 0)
    ctx.RequestRefresh()
end

local function ReconcileStandalone()
    if Bridge or initializationFailed or not loginReady or not storeReady or not addon.PortalCombat.CanInteract() then
        return
    end
    local enabled = Plugin:GetSetting(1, "Enabled")
    if not enabled and not Plugin._portalConstructed then
        return
    end
    if not Plugin._portalConstructed then
        initializationFailed = true
        Plugin:OnLoad()
        local position = Plugin:GetSetting(1, "Position")
        ApplyPosition(nil, position)
        movement = UI.Movement:Create(Services, Plugin.frame, {
            label = L.PLU_VE_PORTAL,
            getPosition = function()
                return Plugin:GetSetting(1, "Position")
            end,
            applyPosition = ApplyPosition,
            onSelect = function()
                Boot.ShowSettings()
            end,
            canEdit = function()
                return Plugin._portalActive and addon.PortalCombat.CanInteract()
            end,
            onEditChanged = function(_, active)
                ctx.state.isEditModeActive = active
                addon.PortalNavigation.HideSearch()
                if addon.PortalCombat.CanInteract() then
                    ctx.Refresh()
                else
                    ctx.RequestRefresh()
                end
            end,
        })
        ctx.movement = movement
        initializationFailed = false
    end
    if enabled and not Plugin._portalActive then
        Plugin:OnEnable()
    elseif not enabled and Plugin._portalActive then
        Plugin:OnDisable()
    end
    movement:SetEnabled(enabled)
    if enabled then
        Plugin:ApplySettings()
    end
    movement:Refresh()
end

local startup = Services.runtime:RegisterReconciler("startup", ReconcileStandalone, function()
    return loginReady and storeReady and addon.PortalCombat.CanInteract()
end)

function Boot.Apply()
    if initializationFailed then
        return
    end
    if Bridge then
        Plugin:ApplySettings()
    else
        if storeReady and not Plugin:GetSetting(1, "Enabled") and Plugin._portalActive then
            Plugin:OnDisable()
            movement:SetEnabled(false)
        end
        Services.runtime:Invalidate(startup)
    end
end

function Boot.EnterEditMode()
    if not addon.PortalCombat.CanInteract() then
        return
    end
    if Bridge or (EditModeManagerFrame and EditModeManagerFrame:CanEnterEditMode()) then
        if dialog then
            dialog:Hide()
        end
        if Bridge then
            Bridge.EnterEditMode()
        else
            securecall("ShowUIPanel", EditModeManagerFrame)
        end
    end
end

function Boot.ResetPosition()
    if initializationFailed or not Plugin.frame or not addon.PortalCombat.CanInteract() then
        return
    end
    if Bridge then
        Bridge.ResetPosition(ctx)
    else
        movement:Reset(CopyTable(addon.PortalDefaults.Position))
    end
end

function Boot.ShowSettings()
    if initializationFailed or not loginReady or (not Bridge and not storeReady) then
        Services.Message(
            (initializationFailed or not loginReady) and L.MSG_PORTAL_NOT_READY or L.MSG_PORTAL_UNSUPPORTED_STORE
        )
        return
    end
    if not dialog then
        local tabs = addon.PortalSchema.Tabs(Plugin, ctx)
        local controls = tabs[1].controls
        table.insert(controls, 1, {
            type = "checkbox",
            label = L.CFG_FP_ENABLED,
            default = true,
            getValue = function()
                return Bridge and Bridge.IsEnabled() or (not Bridge and Plugin:GetSetting(1, "Enabled"))
            end,
            onChange = function(value)
                if Bridge then
                    Bridge.SetEnabled(value)
                else
                    Plugin:SetSetting(1, "Enabled", value)
                end
            end,
        })
        local actions = {
            { label = L.CFG_TAB_EDIT_MODE, onClick = Boot.EnterEditMode },
            { label = L.PLU_PORTAL_RESET_POSITION, onClick = Boot.ResetPosition },
            {
                label = L.PLU_PORTAL_RESCAN,
                onClick = function()
                    Plugin:HandleCommand("scan")
                end,
            },
        }
        dialog = UI.Config.CreateDialog(Services, {
            name = "OrbitPortalSettings",
            title = L.PLU_VE_PORTAL,
            closeLabel = L.CMN_CLOSE,
            tabs = tabs,
            footerButtons = function(tabID)
                return tabID == "layout" and actions or nil
            end,
            get = function(key)
                return Plugin:GetSetting(1, key)
            end,
            set = function(key, value)
                Plugin:SetSetting(1, key, value)
            end,
            onChange = Boot.Apply,
        })
        Services.Message(Bridge and L.MSG_PORTAL_LEGACY_SETTINGS or L.MSG_PORTAL_STANDALONE_SETTINGS)
    end
    dialog:Show()
end

local function RegisterSettings()
    local panel = CreateFrame("Frame")
    panel:Hide()
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(CATEGORY_BUTTON_WIDTH, CATEGORY_BUTTON_HEIGHT)
    Services.pixel:Point(button, "TOPLEFT", panel, "TOPLEFT", CATEGORY_PADDING, -CATEGORY_PADDING)
    button:SetText(L.CFG_SETTINGS_FALLBACK)
    button:SetScript("OnClick", Boot.ShowSettings)
    local category = Settings.RegisterCanvasLayoutCategory(panel, L.PLU_VE_PORTAL)
    Settings.RegisterAddOnCategory(category)
end

SLASH_ORBITPORTAL1 = "/orbitportal"
SlashCmdList.ORBITPORTAL = function(command)
    command = (command or ""):match("^%s*(.-)%s*$"):lower()
    if command == "status" then
        if initializationFailed or not loginReady or (not Bridge and not storeReady) then
            Services.Message(
                (initializationFailed or not loginReady) and L.MSG_PORTAL_NOT_READY or L.MSG_PORTAL_UNSUPPORTED_STORE
            )
        else
            Services.Message(Bridge and L.MSG_PORTAL_LEGACY_SETTINGS or L.MSG_PORTAL_STANDALONE_SETTINGS)
        end
    elseif command == "move" then
        Boot.EnterEditMode()
    elseif command == "reset" then
        Boot.ResetPosition()
    elseif command == "scan" then
        if not initializationFailed and loginReady and (Bridge or storeReady) then
            Plugin:HandleCommand(command)
        end
    else
        Boot.ShowSettings()
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == addonName then
        if not Bridge then
            storeReady = addon.PortalStore:Initialize()
        end
        RegisterSettings()
        boot:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        loginReady = true
        boot:UnregisterEvent("PLAYER_LOGIN")
        if not Bridge then
            if storeReady then
                Services.runtime:Invalidate(startup)
            else
                Services.Message(L.MSG_PORTAL_UNSUPPORTED_STORE)
            end
        end
    end
end)
