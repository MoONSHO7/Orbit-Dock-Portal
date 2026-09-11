local _, addon = ...
local Bridge = addon.PortalOrbit
if not Bridge then
    return
end
local Orbit = Orbit
local OrbitEngine = Orbit.Engine

local ICON_TEXCOORD_MIN = 0.08
local ICON_TEXCOORD_MAX = 0.92
local ICON_BORDER_SCALE = 1.1
local CIRCULAR_MASK_PATH = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local QUESTIONMARK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local STAR_SIZE = 12
local STAR_ATLAS = "transmog-icon-favorite"
local BORDER_ATLAS_SEASONAL = "talents-node-choiceflyout-circle-red"
local BORDER_ATLAS_DEFAULT = "talents-node-choiceflyout-circle-gray"

function Bridge.AttachCanvas(ctx)
    local frame, Plugin, state = ctx.frame, ctx.plugin, ctx.state
    frame.orbitCanvasIconGrid = true
    function frame:CreateCanvasPreview(options)
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
            {
                key = "Timer",
                preview = "5",
                anchorX = "CENTER",
                anchorY = "CENTER",
                offsetX = 0,
                offsetY = 0,
            },
            {
                key = "DungeonScore",
                preview = "285",
                anchorX = "CENTER",
                anchorY = "BOTTOM",
                offsetX = 0,
                offsetY = -2,
            },
            {
                key = "DungeonShort",
                preview = "AA",
                anchorX = "CENTER",
                anchorY = "TOP",
                offsetX = 0,
                offsetY = 2,
            },
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
end
