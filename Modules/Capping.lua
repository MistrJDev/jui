--[[
    Modules/Capping.lua
    ---------------------------------------------------------------------
    Battleground objective/capture progress bars, built on Blizzard's own
    public World State UI feed - GetNumWorldStateUI() / GetWorldStateUIInfo
    - the same data source the default UI's own capture bars are built
    from. This is an original implementation against that public API, not
    a port of BigWigsMods/Capping's per-battleground modules. Arena is
    excluded entirely: this only ever displays inside a battleground.

    UPDATE_WORLD_STATES is deliberately NOT registered here - the current
    client rejects it ("Attempt to register unknown event"). Instead this
    relies on PLAYER_ENTERING_WORLD plus a 1-second poll while actually in
    a battleground, which needs no assumption about which events exist.
--]]

local addonName, ns = ...
local C = Jui.Theme
local db

local MAX_BARS = 5
local bars = {}

local function CreateBar()
    local bar = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    bar:SetSize(220, 20)
    bar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    bar:SetBackdropColor(0.05, 0.05, 0.06, 1)
    bar:SetBackdropBorderColor(unpack(C.borderSoft))
    bar:SetFrameStrata("HIGH")
    bar:Hide()

    bar.Track = bar:CreateTexture(nil, "BACKGROUND")
    bar.Track:SetPoint("TOPLEFT", 1, -1)
    bar.Track:SetPoint("BOTTOMRIGHT", -1, 1)
    bar.Track:SetColorTexture(unpack(C.bgInset))

    bar.Fill = bar:CreateTexture(nil, "ARTWORK")
    bar.Fill:SetPoint("TOPLEFT", 1, -1)
    bar.Fill:SetPoint("BOTTOMLEFT", 1, 1)
    bar.Fill:SetWidth(1)

    bar.Marker = bar:CreateTexture(nil, "OVERLAY")
    bar.Marker:SetSize(2, 20)
    bar.Marker:SetColorTexture(0.9, 0.9, 0.92, 0.9)

    bar.Text = bar:CreateFontString(nil, "OVERLAY")
    bar.Text:SetPoint("CENTER")
    Jui.Fonts:Apply(bar.Text, "Small")
    bar.Text:SetTextColor(0.95, 0.95, 0.96)

    return bar
end

for i = 1, MAX_BARS do
    bars[i] = CreateBar()
end

local function PositionColor(pos)
    if pos <= 33 then
        return 0.82, 0.16, 0.14 -- Horde red
    elseif pos >= 67 then
        return 0.14, 0.46, 0.85 -- Alliance blue
    else
        return 0.78, 0.72, 0.18 -- contested yellow
    end
end

local function ApplyBarLayout()
    local size = db.scale or 1
    local width = 220 * size
    local height = 20 * size
    local gap = 4 * size
    local dir = (db.growDirection == "UP") and 1 or -1

    local shownIndex = 0
    for _, bar in ipairs(bars) do
        if bar:IsShown() then
            shownIndex = shownIndex + 1
            bar:SetSize(width, height)
            bar:ClearAllPoints()
            bar:SetPoint("TOP", UIParent, "CENTER", db.x, db.y + dir * (shownIndex - 1) * (height + gap))
            Jui.Fonts:Apply(bar.Text, math.max(math.floor((db.textSize or 11) * size), 8))
            bar.Marker:SetShown(db.showMarker ~= false)
        end
    end
end

local LiveCapping = {isTesting = false}

local function UpdateCapping()
    if LiveCapping.isTesting then return end

    if not Jui.Modules:IsEnabled("capping") or not Jui.Utils:IsInBattleground() then
        for _, bar in ipairs(bars) do bar:Hide() end
        return
    end

    local shown = 0
    local count = GetNumWorldStateUI()
    for i = 1, count do
        if shown >= (db.maxBars or MAX_BARS) or shown >= MAX_BARS then break end

        local _, state, hidden, text, _, _, _, _, extendedUI, _, position = GetWorldStateUIInfo(i)

        if extendedUI == "CAPTUREPOINT" and state ~= 0 and not hidden then
            shown = shown + 1
            local bar = bars[shown]
            local pct = Jui.Utils:Clamp(position or 50, 0, 100)

            bar.Text:SetText(text or "")

            local fillWidth = math.max((bar:GetWidth() - 2) * (pct / 100), 1)
            bar.Fill:SetWidth(fillWidth)
            bar.Fill:SetColorTexture(PositionColor(pct))

            bar.Marker:ClearAllPoints()
            bar.Marker:SetPoint("CENTER", bar, "LEFT", fillWidth + 1, 0)

            bar:Show()
        end
    end

    for i = shown + 1, MAX_BARS do
        bars[i]:Hide()
    end

    ApplyBarLayout()
end

local function ShowTestBars()
    for _, bar in ipairs(bars) do bar:Hide() end
    bars[1].Text:SetText("Farm (Horde)")
    bars[1].Fill:SetColorTexture(PositionColor(15))
    bars[2].Text:SetText("Mine (Alliance)")
    bars[2].Fill:SetColorTexture(PositionColor(85))

    for i, pct in ipairs({15, 85}) do
        local bar = bars[i]
        local fillWidth = math.max((bar:GetWidth() - 2) * (pct / 100), 1)
        bar.Fill:SetWidth(fillWidth)
        bar.Marker:ClearAllPoints()
        bar.Marker:SetPoint("CENTER", bar, "LEFT", fillWidth + 1, 0)
        bar:Show()
    end
    ApplyBarLayout()
end

local pollTicker

local mod = Jui:RegisterModule({
    id = "capping",
    name = "Capping",
    description = "Battleground objective capture progress bars.",
    enabledByDefault = false,
    category = "gameplay",
})

function mod:OnEnable()
    db = Jui.Database:Get().capping

    self:RegisterEvent("PLAYER_ENTERING_WORLD", UpdateCapping)

    if not pollTicker then
        pollTicker = C_Timer.NewTicker(1, function()
            if Jui.Modules:IsEnabled("capping") and Jui.Utils:IsInBattleground() then
                UpdateCapping()
            end
        end)
    end

    UpdateCapping()
end

function mod:OnDisable()
    if pollTicker then
        pollTicker:Cancel()
        pollTicker = nil
    end
    LiveCapping.isTesting = false
    for _, bar in ipairs(bars) do bar:Hide() end
end

function mod:CreateSettings(parent)
    local emptyState
    if not Jui.Utils:IsInBattleground() then
        emptyState = Jui.UI.Settings:CreateEmptyState(parent,
            "No battleground is currently active.",
            "Enter a battleground to preview objective tracking, or use Test Display below.")
        -- CreateEmptyState already anchors the frame to fill its parent
        -- (SetAllPoints); clear that first so this doesn't leave two
        -- conflicting TOPLEFT/BOTTOMRIGHT anchors on the same frame.
        emptyState:ClearAllPoints()
        emptyState:SetPoint("TOPLEFT", 0, -20)
        emptyState:SetPoint("RIGHT", 0, 0)
        emptyState:SetHeight(70)
    end

    local posGroup = Jui.UI:CreateSection(parent, "Positioning",
        "Only visible in a real battleground with an active objective - use Test Display to preview placement.")
    posGroup:SetPoint("TOPLEFT", 0, emptyState and -100 or 0)
    posGroup:SetSize(440, 140)

    local xSlider = Jui.UI:CreateSlider(posGroup, "X Offset", -500, 500,
        function() return db.x end,
        function(v) db.x = v; ApplyBarLayout() end)
    xSlider:SetPoint("TOPLEFT", 15, posGroup.ContentTop)

    local ySlider = Jui.UI:CreateSlider(posGroup, "Y Offset", -200, 500,
        function() return db.y end,
        function(v) db.y = v; ApplyBarLayout() end)
    ySlider:SetPoint("LEFT", xSlider, "RIGHT", 40, 0)

    -- Parented to `parent`, not posGroup - sitting outside the card
    -- entirely rather than pinned to its top-right corner, which used to
    -- put it directly where the long description above can wrap into on
    -- narrower cards, crushing the button into unreadable overlapping text.
    local testBtn = Jui.UI:CreateButton(parent, LiveCapping.isTesting and "Stop Test" or "Test Display")
    testBtn:SetSize(120, 24)
    testBtn:SetPoint("TOPLEFT", posGroup, "TOPRIGHT", 12, 0)
    testBtn:SetScript("OnClick", function()
        if LiveCapping.isTesting then
            LiveCapping.isTesting = false
            testBtn.Text:SetText("Test Display")
            UpdateCapping()
        else
            LiveCapping.isTesting = true
            testBtn.Text:SetText("Stop Test")
            ShowTestBars()
        end
    end)

    local sizeGroup = Jui.UI:CreateSection(parent, "Sizing")
    sizeGroup:SetPoint("TOPLEFT", posGroup, "BOTTOMLEFT", 0, -12)
    sizeGroup:SetSize(440, 80)

    local sizeSlider = Jui.UI:CreateSlider(sizeGroup, "Bar Scale", 50, 200,
        function() return math.floor((db.scale or 1) * 100) end,
        function(v) db.scale = v / 100; ApplyBarLayout() end)
    sizeSlider:SetPoint("TOPLEFT", 15, sizeGroup.ContentTop)

    local textSlider = Jui.UI:CreateSlider(sizeGroup, "Text Size", 8, 20,
        function() return db.textSize or 11 end,
        function(v) db.textSize = v; ApplyBarLayout() end)
    textSlider:SetPoint("LEFT", sizeSlider, "RIGHT", 55, 0)

    local displayGroup = Jui.UI:CreateSection(parent, "Display")
    displayGroup:SetPoint("TOPLEFT", sizeGroup, "BOTTOMLEFT", 0, -12)
    displayGroup:SetSize(440, 100)

    local maxBarsSlider = Jui.UI:CreateSlider(displayGroup, "Max Bars", 1, MAX_BARS,
        function() return db.maxBars or MAX_BARS end,
        function(v) db.maxBars = v; UpdateCapping() end)
    maxBarsSlider:SetPoint("TOPLEFT", 15, displayGroup.ContentTop)

    local growDropdown = Jui.UI:CreateDropdown(displayGroup, "Growth Direction",
        {{value = "DOWN", text = "Down"}, {value = "UP", text = "Up"}},
        function() return db.growDirection or "DOWN" end,
        function(v) db.growDirection = v; ApplyBarLayout() end)
    growDropdown:SetPoint("LEFT", maxBarsSlider, "RIGHT", 55, 6)

    local markerCB = Jui.UI:CreateCheckbox(displayGroup, "Show Position Marker",
        function() return db.showMarker ~= false end,
        function(v) db.showMarker = v; ApplyBarLayout() end)
    markerCB:SetPoint("TOPLEFT", 15, displayGroup.ContentTop - 52)

    -- Covers both the with-emptyState and without-emptyState cases; a bit
    -- of unused scroll range at the bottom is harmless, unlike content
    -- silently running off the end.
    parent:SetHeight(emptyState and 460 or 360)
end

Jui.UI.Settings:RegisterModulePage("capping", "Capping", "gameplay")
