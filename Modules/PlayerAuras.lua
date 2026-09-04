--[[
    PlayerAuras.lua
    ---------------------------------------------------------------------
    Player Buff / Debuff frame (top-right of the screen) reskin, forked
    from mirror's Theme/Auras.lua player-aura system and rebuilt as a
    small self-contained module. Same rounded-square look as RaidAuras.

    Unlike raid frames, the *position*, *growth direction* and *icons per
    row* of the player buff/debuff frames are owned by Blizzard's own Edit
    Mode. This module re-skins what's drawn inside them and keeps their
    size in sync (exactly what mirror does) - Edit Mode is still where you
    drag / reflow them.
--]]

local addonName, ns = ...
local C = Jui.Theme

-- Declared empty here and assigned inside OnEnable, not at file scope:
-- this file loads before Jui.Database:Initialize() has run.
local db

----------------------------------------------------------------------
-- Colors (kept in sync with RaidAuras.lua)
----------------------------------------------------------------------
local COLOR_BUFF_BORDER = {0, 0, 0, 1}   -- solid black - "nothing special"
local COLOR_ENCHANT_BORDER = {1, 0.82, 0, 1} -- classic gold - weapon enchants

local ICON_MASK = "Interface\\AddOns\\" .. addonName .. "\\Media\\Textures\\AuraMask.png"

local DispelColorCurve = C_CurveUtil.CreateColorCurve()
DispelColorCurve:SetType(Enum.LuaCurveType.Step)
DispelColorCurve:AddPoint(0, DEBUFF_TYPE_NONE_COLOR)
DispelColorCurve:AddPoint(1, DEBUFF_TYPE_MAGIC_COLOR)
DispelColorCurve:AddPoint(2, DEBUFF_TYPE_CURSE_COLOR)
DispelColorCurve:AddPoint(3, DEBUFF_TYPE_DISEASE_COLOR)
DispelColorCurve:AddPoint(4, DEBUFF_TYPE_POISON_COLOR)
DispelColorCurve:AddPoint(9, DEBUFF_TYPE_BLEED_COLOR)
DispelColorCurve:AddPoint(11, DEBUFF_TYPE_BLEED_COLOR)

-- Player auras show a suffixed duration ("10s", "5m") rather than a bare
-- countdown number - matches mirror's player-aura styling.
local AuraDurationFormatter = C_StringUtil.CreateSecondsFormatter()
do
    local mult = 1.5
    local curve = C_CurveUtil.CreateCurve()
    curve:AddPoint(1 + (mult * 60), Enum.SecondsFormatterInterval.Minutes)
    curve:AddPoint(1 + (mult * 3600), Enum.SecondsFormatterInterval.Hours)
    curve:AddPoint(1 + (mult * 86400), Enum.SecondsFormatterInterval.Days)
    AuraDurationFormatter:SetDefaultAbbreviation(Enum.SecondsFormatterAbbreviation.OneLetter)
    AuraDurationFormatter:SetRounding(Enum.SecondsFormatterRounding.Truncate)
    AuraDurationFormatter:SetCanRoundUpLastUnit(true)
    AuraDurationFormatter:SetMinInterval(Enum.SecondsFormatterInterval.Seconds)
    AuraDurationFormatter:SetMaxIntervalCurve(curve)
    AuraDurationFormatter:SetDesiredUnitCount(1)
    AuraDurationFormatter:SetStripIntervalWhitespace(Enum.SecondsFormatterIntervalWhitespace.StripIgnoreLocale)
end

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local JuiPlayerAuraButtons = {} -- [auraButton] = {baseDuration, baseCount, isDebuff}
local showDispelType = true

local function GetTextScale()
    return (db.durationTextSize or 100) / 100,
           (db.countTextSize or 100) / 100
end

local function GetIconSize()
    return db.iconSize or 30
end

----------------------------------------------------------------------
-- Aura button construction (same rounded-square technique as RaidAuras)
----------------------------------------------------------------------
-- category: "buff" | "debuff" | "enchant"
local function CreateAuraButton(auraFrame, category, size)
    auraFrame:SetSize(size, size)

    if auraFrame.juiInit then
        return
    end
    auraFrame.juiInit = true

    local isDebuff = (category == "debuff")
    local inset = 2

    -- Border backing: a flat rounded-square peeking out behind the icon.
    auraFrame.Border = auraFrame:CreateTexture(nil, "BACKGROUND", nil, 0)
    auraFrame.Border:SetPoint("TOPLEFT", auraFrame, "TOPLEFT", -inset, inset)
    auraFrame.Border:SetPoint("BOTTOMRIGHT", auraFrame, "BOTTOMRIGHT", inset, -inset)
    auraFrame.Border:SetColorTexture(1, 1, 1, 1)

    auraFrame.BorderMask = auraFrame:CreateMaskTexture()
    auraFrame.BorderMask:SetTexture(ICON_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    auraFrame.BorderMask:SetAllPoints(auraFrame.Border)
    auraFrame.Border:AddMaskTexture(auraFrame.BorderMask)

    -- Debuffs get a second border layered on top, tinted by dispel type.
    -- Keeping them separate means turning dispel colors off still leaves a
    -- normal black border rather than no border at all.
    if isDebuff then
        auraFrame.DispelBorder = auraFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
        auraFrame.DispelBorder:SetAllPoints(auraFrame.Border)
        auraFrame.DispelBorder:SetColorTexture(1, 1, 1, 1)
        auraFrame.DispelBorder:AddMaskTexture(auraFrame.BorderMask)

        auraFrame:SetAuraBorder(auraFrame.DispelBorder, {
            showIcon = false,
            showWhenHarmful = true,
            showWhenHelpful = false,
            showWithoutDispelType = true,
            customDispelColorCurve = DispelColorCurve,
            style = AuraButtonBorderStyle.Color
        })
        auraFrame.DispelBorder:SetAlpha(showDispelType and 1 or 0)
    end

    -- Icon, rounded to match the border.
    auraFrame.Icon = auraFrame:CreateTexture(nil, "ARTWORK")
    auraFrame.Icon:SetAllPoints(auraFrame)
    auraFrame.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    auraFrame:SetIcon(auraFrame.Icon)

    auraFrame.IconMask = auraFrame:CreateMaskTexture()
    auraFrame.IconMask:SetTexture(ICON_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    auraFrame.IconMask:SetAllPoints(auraFrame.Icon)
    auraFrame.Icon:AddMaskTexture(auraFrame.IconMask)

    local durScale, cntScale = GetTextScale()
    local baseDuration = math.max(math.floor(size / 3.1), 6)
    local baseCount = math.max(math.floor(size / 3), 6)
    local durationFontSize = math.max(math.floor(baseDuration * durScale), 6)
    local countFontSize = math.max(math.floor(baseCount * cntScale), 6)

    -- Stack count
    auraFrame.Count = auraFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    Jui.Fonts:Apply(auraFrame.Count, countFontSize)
    auraFrame.Count:SetPoint("TOPRIGHT", auraFrame.Icon, "TOPRIGHT", -1.5, -1.5)
    auraFrame:SetApplicationCount(auraFrame.Count)

    -- Duration text. Player auras use a suffixed string drawn on the button
    -- rather than a cooldown swipe, so no Cooldown frame is created here.
    auraFrame.CooldownText = auraFrame:CreateFontString(nil, "OVERLAY")
    Jui.Fonts:Apply(auraFrame.CooldownText, durationFontSize)
    auraFrame.CooldownText:SetPoint("BOTTOM", auraFrame.Icon, "BOTTOM", 0, 1)
    auraFrame:SetDurationText(auraFrame.CooldownText, {
        textFormatter = AuraDurationFormatter
    })

    JuiPlayerAuraButtons[auraFrame] = {
        baseDuration = baseDuration,
        baseCount = baseCount,
        isDebuff = isDebuff,
        category = category
    }

    -- Base border color
    if category == "enchant" then
        local color = db.enchantColor or COLOR_ENCHANT_BORDER
        auraFrame.Border:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    else
        auraFrame.Border:SetVertexColor(unpack(COLOR_BUFF_BORDER))
    end

    auraFrame:SetMouseMotionEnabled(db.tooltips ~= false)
end

local function InitPlayerAuraButton(auraFrame, isDebuff, isEnchant)
    local category = isEnchant and "enchant" or (isDebuff and "debuff" or "buff")
    CreateAuraButton(auraFrame, category, GetIconSize())

    -- Right-click to cancel, same as on Blizzard's default buff frame.
    if not isDebuff then
        auraFrame:SetCancelAuraButtons("RightButtonUp")
    end
end

----------------------------------------------------------------------
-- Layout
-- Position / growth direction / icons-per-row are read from Blizzard's
-- own Edit Mode settings on the host frame, same as mirror does. Jui only
-- controls icon size and text scale.
----------------------------------------------------------------------
local function GetAuraFrameLayoutSettings(hostFrame)
    local container = hostFrame.AuraContainer
    return {
        isHorizontal = container.isHorizontal ~= false,
        addIconsToRight = container.addIconsToRight == true,
        addIconsToTop = container.addIconsToTop == true,
        iconStride = container.iconStride or 1,
        iconScale = container.iconScale or 1,
        iconPadding = container.iconPadding or 0,
        showDispelType = container.showDispelType == true
    }
end

local function GetAuraFlowAnchorPoint(settings)
    if settings.addIconsToTop then
        return settings.addIconsToRight and "BOTTOMLEFT" or "BOTTOMRIGHT"
    end
    return settings.addIconsToRight and "TOPLEFT" or "TOPRIGHT"
end

local function SetDebuffDispelTypeShown(shown)
    if showDispelType == shown then
        return
    end
    showDispelType = shown

    local alpha = shown and 1 or 0
    for auraFrame, info in pairs(JuiPlayerAuraButtons) do
        if info.isDebuff and auraFrame.DispelBorder then
            pcall(auraFrame.DispelBorder.SetAlpha, auraFrame.DispelBorder, alpha)
        end
    end
end

local function ResizeHost(hostFrame, settings)
    local maxAuras = (hostFrame == DebuffFrame) and (DEBUFF_MAX_DISPLAY or 16) or (BUFF_MAX_DISPLAY or 32)
    local perRow = math.max(settings.iconStride, 1)
    local size = GetIconSize()

    local iconWidth = size + settings.iconPadding
    local iconHeight = size + settings.iconPadding

    local across = perRow
    local down = math.ceil(maxAuras / perRow)

    local width, height
    if settings.isHorizontal then
        width, height = iconWidth * across, iconHeight * down
    else
        width, height = iconWidth * down, iconHeight * across
    end

    hostFrame:SetSize(width * settings.iconScale, height * settings.iconScale)
end

local function ApplyPlayerAuraLayout(hostFrame)
    local container = hostFrame.juiAuraContainer
    if not container then
        return
    end

    local settings = GetAuraFrameLayoutSettings(hostFrame)
    local anchorPoint = GetAuraFlowAnchorPoint(settings)
    local spacing = settings.iconPadding
    local size = GetIconSize()

    container:SetScale(settings.iconScale)
    container:SetFlowLayoutAnchorPoint(anchorPoint)
    container:SetFlowLayoutGrowthDirection(
        settings.addIconsToRight and AnchorUtil.FlowDirection.Right or AnchorUtil.FlowDirection.Left,
        settings.addIconsToTop and AnchorUtil.FlowDirection.Up or AnchorUtil.FlowDirection.Down)

    local perRow = settings.isHorizontal and settings.iconStride or 1
    container:SetFlowLayoutMaximumLineSize(perRow * (size + spacing))

    local layout = {elementSpacing = spacing, lineSpacing = spacing}
    container:SetAuraGroupLayout(hostFrame == DebuffFrame and "PlayerDebuffs" or "PlayerBuffs", layout)

    if hostFrame == BuffFrame then
        container:SetItemEnchantmentLayout({
            placement = CustomAuraContainerItemEnchantmentPlacement.BeforeAuraGroups,
            elementSpacing = layout.elementSpacing,
            lineSpacing = layout.lineSpacing
        })
    end

    if hostFrame == DebuffFrame then
        SetDebuffDispelTypeShown(settings.showDispelType)
    end

    container:ClearAllPoints()
    container:SetPoint(anchorPoint, hostFrame, anchorPoint, 0, 0)

    ResizeHost(hostFrame, settings)
end

----------------------------------------------------------------------
-- Container setup
----------------------------------------------------------------------
local function CreatePlayerAuraContainer(hostFrame, isDebuff)
    local container = CreateFrame("AuraContainer", nil, hostFrame, "CustomAuraContainerTemplate")
    container:SetUnit("player")
    container:SetEnabled(true)

    local filterString = isDebuff and AuraUtil.CreateFilterString(AuraUtil.AuraFilters.Harmful)
        or AuraUtil.CreateFilterString(AuraUtil.AuraFilters.Helpful)

    -- "Show Buffs"/"Show Debuffs" work the same way RaidAuras' visibility
    -- toggles do: capping maxFrameCount at 0 rather than trying to hide
    -- the container itself, since AddAuraGroup doesn't offer a simpler
    -- on/off switch.
    local hidden = isDebuff and (db.showDebuffs == false) or (not isDebuff and db.showBuffs == false)
    local maxCount = hidden and 0 or (isDebuff and (DEBUFF_MAX_DISPLAY or 16) or (BUFF_MAX_DISPLAY or 32))

    container:AddAuraGroup(isDebuff and "PlayerDebuffs" or "PlayerBuffs", filterString, {
        maxFrameCount = maxCount,
        initializeFrame = function(auraFrame)
            InitPlayerAuraButton(auraFrame, isDebuff, false)
        end
    })

    -- Weapon enchants (temporary buffs) live in the buff container.
    -- AddItemEnchantment doesn't have a maxFrameCount-style visibility
    -- knob, so "Show Enchants" skips adding them at all instead.
    if not isDebuff and db.showEnchants ~= false then
        for _, slot in ipairs({AuraContainerItemEnchantmentSlot.MainHand,
                               AuraContainerItemEnchantmentSlot.OffHand,
                               AuraContainerItemEnchantmentSlot.Ranged}) do
            container:AddItemEnchantment(slot, {
                initializeFrame = function(auraFrame)
                    InitPlayerAuraButton(auraFrame, false, true)
                end
            })
        end
    end

    hostFrame.juiAuraContainer = container
    ApplyPlayerAuraLayout(hostFrame)

    return container
end

----------------------------------------------------------------------
-- Hide Blizzard's default icons (same approach mirror uses)
----------------------------------------------------------------------
local function DisableDefaultPlayerAuras()
    for _, hostFrame in ipairs({BuffFrame, DebuffFrame}) do
        hostFrame:UnregisterAllEvents()
        hostFrame.AuraContainer:UnregisterAllEvents()
        hostFrame.AuraContainer:Hide()
        hostFrame:SetScript("OnUpdate", nil)

        for _, auraFrame in ipairs(hostFrame.auraFrames or {}) do
            if not auraFrame.isAuraAnchor then
                auraFrame:SetScript("OnUpdate", nil)
                auraFrame:Hide()
            else
                -- Blizzard keeps re-showing this internal anchor; keep putting
                -- it back down whenever it tries.
                auraFrame:Hide()
                if not auraFrame.juiShowHooked then
                    auraFrame.juiShowHooked = true
                    hooksecurefunc(auraFrame, "Show", function(self) self:Hide() end)
                end

                if auraFrame.Duration and not auraFrame.Duration.juiShowHooked then
                    auraFrame.Duration.juiShowHooked = true
                    auraFrame.Duration:Hide()
                    hooksecurefunc(auraFrame.Duration, "Show", function(text) text:Hide() end)
                end
            end
        end
    end

    pcall(CVarCallbackRegistry.UnregisterCallback, CVarCallbackRegistry, 'consolidateBuffs', BuffFrame)
    pcall(CVarCallbackRegistry.UnregisterCallback, CVarCallbackRegistry, 'collapseExpandBuffs', BuffFrame)

    -- These two don't exist on every client build, so don't hard-fail on them.
    if BuffFrame.ConsolidatedBuffs then BuffFrame.ConsolidatedBuffs:Hide() end
    if BuffFrame.CollapseAndExpandButton then BuffFrame.CollapseAndExpandButton:Hide() end
end

----------------------------------------------------------------------
-- Enable
----------------------------------------------------------------------
local hooked = false

local function EnablePlayerAuras()
    if hooked then return end
    hooked = true

    CreatePlayerAuraContainer(BuffFrame, false)
    CreatePlayerAuraContainer(DebuffFrame, true)
    DisableDefaultPlayerAuras()

    -- Edit Mode changes (position, stride, scale, padding) come through here.
    for _, hostFrame in ipairs({BuffFrame, DebuffFrame}) do
        hooksecurefunc(hostFrame, "UpdateSystemSetting", function(self)
            ApplyPlayerAuraLayout(self)
        end)
    end
end

----------------------------------------------------------------------
-- Live-update helpers
----------------------------------------------------------------------
local function UpdateAllLayouts()
    if not hooked then return end

    -- Re-size every existing button, then re-flow both containers.
    local size = GetIconSize()
    for auraFrame in pairs(JuiPlayerAuraButtons) do
        pcall(auraFrame.SetSize, auraFrame, size, size)
    end

    for _, hostFrame in ipairs({BuffFrame, DebuffFrame}) do
        ApplyPlayerAuraLayout(hostFrame)
    end
end

local function UpdateAllTextSizes()
    local durScale, cntScale = GetTextScale()
    for auraFrame, info in pairs(JuiPlayerAuraButtons) do
        local durSize = math.max(math.floor(info.baseDuration * durScale), 6)
        local cntSize = math.max(math.floor(info.baseCount * cntScale), 6)
        Jui.Fonts:Apply(auraFrame.CooldownText, durSize)
        Jui.Fonts:Apply(auraFrame.Count, cntSize)
    end
end

local function UpdateAllTooltips()
    local enabled = db.tooltips ~= false
    for auraFrame in pairs(JuiPlayerAuraButtons) do
        pcall(auraFrame.SetMouseMotionEnabled, auraFrame, enabled)
    end
end

-- "Show Buffs"/"Show Debuffs" apply live via SetAuraGroupMaxFrameCount
-- (same technique RaidAuras uses for its defensive-visibility toggle).
-- "Show Enchants" can't work this way - AddItemEnchantment has no
-- equivalent live toggle, so that one needs a reload, same honest
-- trade-off as enabling/disabling the whole module.
local function UpdateAllVisibility()
    for _, hostFrame in ipairs({BuffFrame, DebuffFrame}) do
        local container = hostFrame.juiAuraContainer
        if container then
            local isDebuff = (hostFrame == DebuffFrame)
            local hidden = isDebuff and (db.showDebuffs == false) or (not isDebuff and db.showBuffs == false)
            local maxCount = hidden and 0 or (isDebuff and (DEBUFF_MAX_DISPLAY or 16) or (BUFF_MAX_DISPLAY or 32))
            pcall(container.SetAuraGroupMaxFrameCount, container,
                isDebuff and "PlayerDebuffs" or "PlayerBuffs", maxCount)
        end
    end
end

----------------------------------------------------------------------

----------------------------------------------------------------------
-- Module registration
----------------------------------------------------------------------
local mod = Jui:RegisterModule({
    id = "playerAuras",
    name = "Player Auras",
    description = "Custom buff/debuff frame reskin, top-right of the screen.",
    enabledByDefault = false,
    category = "auras",
})

function mod:OnEnable()
    db = Jui.Database:Get().playerAuras
    EnablePlayerAuras()
end

-- Same honest caveat as Raid Auras: the frame hooks here are permanent
-- hooksecurefuncs, so disabling doesn't fully undo them until a reload.
function mod:OnDisable()
end

function mod:CreateSettings(parent)
    local GROUP_WIDTH = 650

    local reloadNote = Jui.UI:CreateText(parent, "Small", C.textFaint)
    reloadNote:SetPoint("TOPLEFT", 0, 0)
    reloadNote:SetText("Enabling/disabling this module fully takes effect after a UI reload.")

    local generalGroup = Jui.UI:CreateSection(parent, "General", nil, GROUP_WIDTH)
    generalGroup:SetPoint("TOPLEFT", reloadNote, "BOTTOMLEFT", 0, -10)
    generalGroup:SetSize(GROUP_WIDTH, 105)

    local tooltipCB = Jui.UI:CreateCheckbox(generalGroup, "Aura Tooltips",
        function() return db.tooltips end,
        function(v) db.tooltips = v; UpdateAllTooltips() end)
    tooltipCB:SetPoint("TOPLEFT", 15, generalGroup.ContentTop)

    local editModeNote = Jui.UI:CreateText(generalGroup, "Small", C.textFaint)
    editModeNote:SetPoint("TOPLEFT", 15, generalGroup.ContentTop - 34)
    editModeNote:SetPoint("RIGHT", generalGroup, "RIGHT", -15, 0)
    editModeNote:SetJustifyH("LEFT")
    editModeNote:SetText("Position, growth direction and icons-per-row are still set in Blizzard's Edit Mode (Esc > Edit Mode) on the Buff/Debuff frames. Jui only restyles what's drawn inside them.")

    local iconsGroup = Jui.UI:CreateSection(parent, "Icons", nil, GROUP_WIDTH)
    iconsGroup:SetPoint("TOPLEFT", generalGroup, "BOTTOMLEFT", 0, -18)
    iconsGroup:SetSize(GROUP_WIDTH, 90)

    local iconSizeSlider = Jui.UI:CreateSlider(iconsGroup, "Icon Size", 16, 50,
        function() return db.iconSize end,
        function(v) db.iconSize = v; UpdateAllLayouts() end)
    iconSizeSlider:SetPoint("TOPLEFT", 15, iconsGroup.ContentTop)

    local textGroup = Jui.UI:CreateSection(parent, "Text", nil, GROUP_WIDTH)
    textGroup:SetPoint("TOPLEFT", iconsGroup, "BOTTOMLEFT", 0, -18)
    textGroup:SetSize(GROUP_WIDTH, 90)

    local durTextSlider = Jui.UI:CreateSlider(textGroup, "Duration Text Size", 50, 200,
        function() return db.durationTextSize end,
        function(v) db.durationTextSize = v; UpdateAllTextSizes() end)
    durTextSlider:SetPoint("TOPLEFT", 15, textGroup.ContentTop)

    local cntTextSlider = Jui.UI:CreateSlider(textGroup, "Stack Count Text Size", 50, 200,
        function() return db.countTextSize end,
        function(v) db.countTextSize = v; UpdateAllTextSizes() end)
    cntTextSlider:SetPoint("LEFT", durTextSlider, "RIGHT", 55, 0)

    local displayGroup = Jui.UI:CreateSection(parent, "Display", nil, GROUP_WIDTH)
    displayGroup:SetPoint("TOPLEFT", textGroup, "BOTTOMLEFT", 0, -18)
    displayGroup:SetSize(GROUP_WIDTH, 70)

    local showBuffsCB = Jui.UI:CreateCheckbox(displayGroup, "Show Buffs",
        function() return db.showBuffs ~= false end,
        function(v) db.showBuffs = v; UpdateAllVisibility() end)
    showBuffsCB:SetPoint("TOPLEFT", 15, displayGroup.ContentTop)

    local showDebuffsCB = Jui.UI:CreateCheckbox(displayGroup, "Show Debuffs",
        function() return db.showDebuffs ~= false end,
        function(v) db.showDebuffs = v; UpdateAllVisibility() end)
    showDebuffsCB:SetPoint("TOPLEFT", 225, displayGroup.ContentTop)

    local showEnchantsCB = Jui.UI:CreateCheckbox(displayGroup, "Show Enchants (reload)",
        function() return db.showEnchants ~= false end,
        function(v) db.showEnchants = v end)
    showEnchantsCB:SetPoint("TOPLEFT", 435, displayGroup.ContentTop)
    Jui.UI:AttachTooltip(showEnchantsCB, "Show Enchants",
        "Weapon enchant icons are only added to the buff frame when it's first built, so this one needs a UI reload to take effect - unlike Show Buffs/Show Debuffs above, which apply immediately.")

    local themeGroup = Jui.UI:CreateSection(parent, "Theme", nil, GROUP_WIDTH)
    themeGroup:SetPoint("TOPLEFT", displayGroup, "BOTTOMLEFT", 0, -18)
    themeGroup:SetSize(GROUP_WIDTH, 70)

    local swatch = CreateFrame("Button", nil, themeGroup, "BackdropTemplate")
    swatch:SetSize(60, 22)
    swatch:SetPoint("TOPLEFT", 15, themeGroup.ContentTop)
    swatch:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    swatch:SetBackdropBorderColor(unpack(C.borderSoft))

    local swatchLabel = Jui.UI:CreateText(themeGroup, "Small", C.textSecond)
    swatchLabel:SetPoint("BOTTOMLEFT", swatch, "TOPLEFT", 0, 5)
    swatchLabel:SetText("Enchant Border Color")

    local function RefreshSwatch()
        local color = db.enchantColor or COLOR_ENCHANT_BORDER
        swatch:SetBackdropColor(color[1], color[2], color[3])
    end
    swatch:SetScript("OnShow", RefreshSwatch)
    RefreshSwatch()

    swatch:SetScript("OnClick", function()
        local color = db.enchantColor or COLOR_ENCHANT_BORDER
        ColorPickerFrame:SetupColorPickerAndShow({
            r = color[1], g = color[2], b = color[3],
            swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                db.enchantColor = {nr, ng, nb}
                RefreshSwatch()
                for auraFrame, info in pairs(JuiPlayerAuraButtons) do
                    if info.category == "enchant" then
                        pcall(auraFrame.Border.SetVertexColor, auraFrame.Border, nr, ng, nb, 1)
                    end
                end
            end,
            cancelFunc = function(prev)
                if prev then
                    db.enchantColor = {prev.r, prev.g, prev.b}
                    RefreshSwatch()
                end
            end,
        })
    end)

    parent:SetHeight(560)
end

Jui.UI.Settings:RegisterModulePage("playerAuras", "Player Auras", "auras")
