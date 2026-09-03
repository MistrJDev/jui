--[[
    Modules/QueueTimer.lua
    ---------------------------------------------------------------------
    Shows time-in-queue and estimated wait while queued for a battleground.
--]]

local addonName, ns = ...

local TimerFrame = CreateFrame("Frame", "JuiQueueTimer", UIParent)
TimerFrame:SetSize(220, 50)
TimerFrame:SetClampedToScreen(true)
TimerFrame:Hide()

TimerFrame.queueText = TimerFrame:CreateFontString(nil, "OVERLAY")
TimerFrame.queueText:SetPoint("TOP", TimerFrame, "TOP", 0, 0)

TimerFrame.estimatedText = TimerFrame:CreateFontString(nil, "OVERLAY")
TimerFrame.estimatedText:SetPoint("TOP", TimerFrame.queueText, "BOTTOM", 0, -2)

local function UpdateDisplay()
    local db = Jui.Database:Get().queueTimer

    TimerFrame:ClearAllPoints()
    TimerFrame:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)

    Jui.Fonts:Apply(TimerFrame.queueText, db.fontSize)
    Jui.Fonts:Apply(TimerFrame.estimatedText, db.fontSize - 4)

    if TimerFrame.isTesting then
        TimerFrame:Show()
        TimerFrame.queueText:SetText("In Queue: 04:20")
        TimerFrame.estimatedText:SetText("Estimated: 05:00")
        return
    end

    if IsInInstance() then
        TimerFrame:Hide()
        return
    end

    local queued = false
    for i = 1, 3 do
        local status = GetBattlefieldStatus(i)
        if status == "queued" or status == "confirm" then
            local ms = GetBattlefieldTimeWaited(i)
            local est = GetBattlefieldEstimatedWaitTime(i)
            TimerFrame.queueText:SetText("Time in queue: " .. Jui.Utils:FormatTime(ms / 1000))
            TimerFrame.estimatedText:SetText("Estimated: " ..
                (est > 0 and Jui.Utils:FormatTime(est / 1000) or "Calculating..."))
            queued = true
            break
        end
    end

    TimerFrame:SetShown(queued)
end

local ticker

local mod = Jui:RegisterModule({
    id = "queueTimer",
    name = "Queue Timer",
    description = "Shows time in queue and the estimated wait.",
    enabledByDefault = true,
    category = "gameplay",
})

function mod:OnEnable()
    if not ticker then
        ticker = C_Timer.NewTicker(0.5, UpdateDisplay)
    end
    UpdateDisplay()
end

function mod:OnDisable()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    TimerFrame.isTesting = false
    TimerFrame:Hide()
end

function mod:CreateSettings(parent)
    local db = Jui.Database:Get().queueTimer

    local posGroup = Jui.UI:CreateSection(parent, "Positioning")
    posGroup:SetPoint("TOPLEFT", 0, 0)
    posGroup:SetSize(440, 90)

    local xSlider = Jui.UI:CreateSlider(posGroup, "X Offset", -500, 500,
        function() return db.x end,
        function(v) db.x = v; UpdateDisplay() end)
    xSlider:SetPoint("TOPLEFT", 15, posGroup.ContentTop)

    local ySlider = Jui.UI:CreateSlider(posGroup, "Y Offset", -500, 500,
        function() return db.y end,
        function(v) db.y = v; UpdateDisplay() end)
    ySlider:SetPoint("LEFT", xSlider, "RIGHT", 40, 0)

    local sizeGroup = Jui.UI:CreateSection(parent, "Sizing")
    sizeGroup:SetPoint("TOPLEFT", posGroup, "BOTTOMLEFT", 0, -12)
    sizeGroup:SetSize(440, 80)

    local fontSlider = Jui.UI:CreateSlider(sizeGroup, "Font Size", 10, 40,
        function() return db.fontSize end,
        function(v) db.fontSize = v; UpdateDisplay() end)
    fontSlider:SetPoint("TOPLEFT", 15, sizeGroup.ContentTop)

    local testBtn = Jui.UI:CreateButton(parent, "Test Display")
    testBtn:SetPoint("TOPLEFT", posGroup, "TOPRIGHT", 12, 0)
    testBtn:SetSize(120, 24)
    testBtn:SetScript("OnClick", function()
        TimerFrame.isTesting = not TimerFrame.isTesting
        testBtn.Text:SetText(TimerFrame.isTesting and "Stop Test" or "Test Display")
        UpdateDisplay()
    end)

    parent:SetHeight(190)
end

Jui.UI.Settings:RegisterModulePage("queueTimer", "Queue Timer", "gameplay")
