--[[
    Modules/LossOfControl.lua
    ---------------------------------------------------------------------
    Full-screen "you're stunned/feared/etc" alert, built on
    C_LossOfControl.GetActiveLossOfControlData() directly rather than
    reverse-engineering Blizzard's own LossOfControlFrame's private
    sub-elements.
--]]

local addonName, ns = ...
local C = Jui.Theme

local LocFrame = CreateFrame("Frame", "JuiLocFrame", UIParent)
LocFrame:SetSize(40, 40)
LocFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -60)
LocFrame:SetFrameStrata("HIGH")
LocFrame:Hide()

LocFrame.Icon = LocFrame:CreateTexture(nil, "ARTWORK")
LocFrame.Icon:SetAllPoints()
LocFrame.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

LocFrame.Border = LocFrame:CreateTexture(nil, "BACKGROUND")
LocFrame.Border:SetPoint("TOPLEFT", -1, 1)
LocFrame.Border:SetPoint("BOTTOMRIGHT", 1, -1)
LocFrame.Border:SetColorTexture(0, 0, 0, 1)

LocFrame.Cooldown = CreateFrame("Cooldown", nil, LocFrame, "CooldownFrameTemplate")
LocFrame.Cooldown:SetAllPoints(LocFrame.Icon)
LocFrame.Cooldown:SetReverse(true)
LocFrame.Cooldown:SetDrawBling(false)
LocFrame.Cooldown:SetHideCountdownNumbers(true)

LocFrame.TypeText = LocFrame:CreateFontString(nil, "OVERLAY")
LocFrame.TypeText:SetPoint("BOTTOM", LocFrame, "TOP", 0, 6)
Jui.Fonts:Apply(LocFrame.TypeText, 16, "OUTLINE")
LocFrame.TypeText:SetTextColor(unpack(C.danger))

LocFrame.CounterText = LocFrame:CreateFontString(nil, "OVERLAY")
LocFrame.CounterText:SetPoint("CENTER", LocFrame.Icon, "CENTER", 0, 0)
Jui.Fonts:Apply(LocFrame.CounterText, 18, "OUTLINE")
LocFrame.CounterText:SetTextColor(1, 1, 1)

-- Applies every user-configurable display setting: position, icon size,
-- type/counter text sizes, type text color, and whether each text
-- element shows at all. Called both on layout changes and whenever a new
-- LoC event fires, so live settings changes take effect immediately
-- without needing to re-trigger the CC.
local function ApplyLayout()
    local db = Jui.Database:Get().lossOfControl
    LocFrame:ClearAllPoints()
    LocFrame:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
    LocFrame:SetSize(db.size, db.size)

    Jui.Fonts:Apply(LocFrame.TypeText, db.typeTextSize or 16, "OUTLINE")
    local color = db.typeTextColor or {1, 0.25, 0.2}
    LocFrame.TypeText:SetTextColor(color[1], color[2], color[3])
    LocFrame.TypeText:SetShown(db.showTypeText ~= false and LocFrame.activeData ~= nil)

    Jui.Fonts:Apply(LocFrame.CounterText, db.counterTextSize or 18, "OUTLINE")
end

LocFrame:SetScript("OnUpdate", function(self)
    local data = self.activeData
    if not data then return end
    if data.startTime and data.duration and data.duration > 0 then
        local remaining = (data.startTime + data.duration) - GetTime()
        if remaining <= 0 then
            self:Hide()
            self.activeData = nil
            return
        end
        self.CounterText:SetText(string.format("%.1f", remaining))
    end
end)

local function GetActiveLoC()
    local count = C_LossOfControl.GetActiveLossOfControlDataCount()
    local best
    for i = 1, count do
        local data = C_LossOfControl.GetActiveLossOfControlData(i)
        if data and data.displayText and (not best or (data.priority or 0) > (best.priority or 0)) then
            best = data
        end
    end
    return best
end

local function ShowLoC(data)
    LocFrame.activeData = data
    LocFrame.TypeText:SetText((data.displayText or "Controlled"):upper())

    if data.iconTexture then
        LocFrame.Icon:SetTexture(data.iconTexture)
    end

    local db = Jui.Database:Get().lossOfControl
    local wantsCounter = db.showCounter ~= false

    if wantsCounter and data.startTime and data.duration and data.duration > 0 then
        LocFrame.Cooldown:SetCooldown(data.startTime, data.duration)
        LocFrame.Cooldown:Show()
        LocFrame.CounterText:Show()
    else
        LocFrame.Cooldown:Hide()
        LocFrame.CounterText:Hide()
    end

    ApplyLayout()
    LocFrame:Show()
end

local function RefreshFromRealData()
    if LocFrame.isTesting then return end
    local data = GetActiveLoC()
    if data then
        ShowLoC(data)
    else
        LocFrame.activeData = nil
        LocFrame:Hide()
    end
end

local mod = Jui:RegisterModule({
    id = "lossOfControl",
    name = "Loss of Control",
    description = "Full-screen alert when stunned, feared, silenced or rooted.",
    enabledByDefault = true,
    category = "gameplay",
})

function mod:OnEnable()
    self:RegisterEvent("LOSS_OF_CONTROL_UPDATE", RefreshFromRealData)
    self:RegisterEvent("LOSS_OF_CONTROL_ADDED", RefreshFromRealData)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", RefreshFromRealData)

    if LossOfControlFrame then
        LossOfControlFrame:Hide()
        if not LossOfControlFrame.juiShowHooked then
            LossOfControlFrame.juiShowHooked = true
            hooksecurefunc(LossOfControlFrame, "Show", function(self) self:Hide() end)
        end
    end

    RefreshFromRealData()
end

function mod:OnDisable()
    LocFrame.activeData = nil
    LocFrame.isTesting = false
    LocFrame:Hide()
end

function mod:CreateSettings(parent)
    local posGroup = Jui.UI:CreateSection(parent, "Positioning")
    posGroup:SetPoint("TOPLEFT", 0, 0)
    posGroup:SetSize(440, 80)

    local db = Jui.Database:Get().lossOfControl

    local xSlider = Jui.UI:CreateSlider(posGroup, "X Offset", -500, 500,
        function() return db.x end,
        function(v) db.x = v; ApplyLayout() end)
    xSlider:SetPoint("TOPLEFT", 15, posGroup.ContentTop)

    local ySlider = Jui.UI:CreateSlider(posGroup, "Y Offset", -500, 500,
        function() return db.y end,
        function(v) db.y = v; ApplyLayout() end)
    ySlider:SetPoint("LEFT", xSlider, "RIGHT", 40, 0)

    local sizeGroup = Jui.UI:CreateSection(parent, "Sizing")
    sizeGroup:SetPoint("TOPLEFT", posGroup, "BOTTOMLEFT", 0, -12)
    sizeGroup:SetSize(440, 80)

    local sizeSlider = Jui.UI:CreateSlider(sizeGroup, "Icon Size", 20, 120,
        function() return db.size end,
        function(v) db.size = v; ApplyLayout() end)
    sizeSlider:SetPoint("TOPLEFT", 15, sizeGroup.ContentTop)

    local displayGroup = Jui.UI:CreateSection(parent, "Display")
    displayGroup:SetPoint("TOPLEFT", sizeGroup, "BOTTOMLEFT", 0, -12)
    displayGroup:SetSize(440, 130)

    local showTypeCB = Jui.UI:CreateCheckbox(displayGroup, "Show Type Text",
        function() return db.showTypeText ~= false end,
        function(v) db.showTypeText = v; ApplyLayout() end)
    showTypeCB:SetPoint("TOPLEFT", 15, displayGroup.ContentTop)

    local showCounterCB = Jui.UI:CreateCheckbox(displayGroup, "Show Timer",
        function() return db.showCounter ~= false end,
        function(v)
            db.showCounter = v
            if LocFrame.activeData then ShowLoC(LocFrame.activeData) end
        end)
    showCounterCB:SetPoint("TOPLEFT", 225, displayGroup.ContentTop)

    local typeTextSlider = Jui.UI:CreateSlider(displayGroup, "Type Text Size", 10, 32,
        function() return db.typeTextSize or 16 end,
        function(v) db.typeTextSize = v; ApplyLayout() end)
    typeTextSlider:SetPoint("TOPLEFT", 15, displayGroup.ContentTop - 52)

    local counterTextSlider = Jui.UI:CreateSlider(displayGroup, "Timer Text Size", 10, 32,
        function() return db.counterTextSize or 18 end,
        function(v) db.counterTextSize = v; ApplyLayout() end)
    counterTextSlider:SetPoint("LEFT", typeTextSlider, "RIGHT", 55, 0)

    local themeGroup = Jui.UI:CreateSection(parent, "Theme")
    themeGroup:SetPoint("TOPLEFT", displayGroup, "BOTTOMLEFT", 0, -12)
    themeGroup:SetSize(440, 80)

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
    swatchLabel:SetText("Type Text Color")

    local function RefreshSwatch()
        local color = db.typeTextColor or {1, 0.25, 0.2}
        swatch:SetBackdropColor(color[1], color[2], color[3])
    end
    swatch:SetScript("OnShow", RefreshSwatch)
    RefreshSwatch()

    swatch:SetScript("OnClick", function()
        local color = db.typeTextColor or {1, 0.25, 0.2}
        ColorPickerFrame:SetupColorPickerAndShow({
            r = color[1], g = color[2], b = color[3],
            swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                db.typeTextColor = {nr, ng, nb}
                RefreshSwatch()
                ApplyLayout()
            end,
            cancelFunc = function(prev)
                if prev then
                    db.typeTextColor = {prev.r, prev.g, prev.b}
                    RefreshSwatch()
                    ApplyLayout()
                end
            end,
        })
    end)

    local testBtn = Jui.UI:CreateButton(parent, LocFrame.isTesting and "Stop Test" or "Test Display")
    testBtn:SetPoint("TOPLEFT", posGroup, "TOPRIGHT", 12, 0)
    testBtn:SetSize(120, 24)
    testBtn:SetScript("OnClick", function()
        if LocFrame.isTesting then
            LocFrame.isTesting = false
            LocFrame.activeData = nil
            LocFrame:Hide()
            testBtn.Text:SetText("Test Display")
            RefreshFromRealData()
        else
            LocFrame.isTesting = true
            testBtn.Text:SetText("Stop Test")
            ShowLoC({
                displayText = "Stunned",
                iconTexture = "Interface\\Icons\\Spell_Frost_Stun",
                startTime = GetTime(),
                duration = 5,
                priority = 0,
            })
        end
    end)

    parent:SetHeight(390)
end

Jui.UI.Settings:RegisterModulePage("lossOfControl", "Loss of Control", "gameplay")
