--[[
    Modules/Winrate.lua
    ---------------------------------------------------------------------
    Adds season winrate text onto Blizzard's own Conquest/PvP queue frame.
--]]

local addonName, ns = ...

local function SetupWinrateText(button)
    if not button or button.WinrateText then return end
    button.WinrateText = button:CreateFontString(nil, "OVERLAY")
end

local function RefreshJuiWinrates()
    if not ConquestFrame or not ConquestFrame:IsShown() then return end
    local db = Jui.Database:Get().winrate

    local brackets = {
        {frame = ConquestFrame.Arena2v2, id = 1},
        {frame = ConquestFrame.Arena3v3, id = 2},
        {frame = ConquestFrame.RatedBGBlitz, id = 9},
    }

    for _, data in ipairs(brackets) do
        local btn = data.frame
        if btn then
            SetupWinrateText(btn)

            local _, _, _, seasonPlayed, seasonWon = GetPersonalRatedInfo(data.id)
            local w = tonumber(seasonWon) or 0
            local p = tonumber(seasonPlayed) or 0

            btn.WinrateText:ClearAllPoints()
            btn.WinrateText:SetPoint("RIGHT", btn, "RIGHT", db.x, db.y)
            Jui.Fonts:Apply(btn.WinrateText, db.size)

            if p > 0 then
                btn.WinrateText:SetText(string.format("%.1f%%", (w / p) * 100))
            else
                btn.WinrateText:SetText("/")
            end
        end
    end
end

local mod = Jui:RegisterModule({
    id = "winrate",
    name = "Winrate",
    description = "Adds your season winrate to the PvP queue frame.",
    enabledByDefault = true,
    category = "gameplay",
})

local hooked = false

function mod:OnEnable()
    if hooked then
        RefreshJuiWinrates()
        return
    end
    hooked = true

    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_PVPUI") then
        if ConquestFrame then
            ConquestFrame:HookScript("OnShow", function()
                RequestRatedInfo()
                C_Timer.NewTicker(0.2, function()
                    if not Jui.Modules:IsEnabled("winrate") then return end
                    RefreshJuiWinrates()
                    if not ConquestFrame:IsShown() then return end
                end, 15)
            end)
            hooksecurefunc("ConquestFrame_Update", function()
                if Jui.Modules:IsEnabled("winrate") then RefreshJuiWinrates() end
            end)
        end
    else
        self:RegisterEvent("ADDON_LOADED", function(event, loaded)
            if loaded ~= "Blizzard_PVPUI" or not ConquestFrame then return end
            ConquestFrame:HookScript("OnShow", function()
                RequestRatedInfo()
                C_Timer.NewTicker(0.2, function()
                    if not Jui.Modules:IsEnabled("winrate") then return end
                    RefreshJuiWinrates()
                end, 15)
            end)
            hooksecurefunc("ConquestFrame_Update", function()
                if Jui.Modules:IsEnabled("winrate") then RefreshJuiWinrates() end
            end)
        end)
    end
end

function mod:OnDisable()
    if ConquestFrame and ConquestFrame.Arena2v2 and ConquestFrame.Arena2v2.WinrateText then
        ConquestFrame.Arena2v2.WinrateText:SetText("")
    end
end

function mod:CreateSettings(parent)
    local db = Jui.Database:Get().winrate

    local posGroup = Jui.UI:CreateSection(parent, "Positioning")
    posGroup:SetPoint("TOPLEFT", 0, 0)
    posGroup:SetSize(440, 90)

    local xSlider = Jui.UI:CreateSlider(posGroup, "X Offset", -150, 0,
        function() return db.x end,
        function(v) db.x = v; RefreshJuiWinrates() end)
    xSlider:SetPoint("TOPLEFT", 15, posGroup.ContentTop)

    local ySlider = Jui.UI:CreateSlider(posGroup, "Y Offset", -50, 50,
        function() return db.y end,
        function(v) db.y = v; RefreshJuiWinrates() end)
    ySlider:SetPoint("LEFT", xSlider, "RIGHT", 40, 0)

    local sizeGroup = Jui.UI:CreateSection(parent, "Sizing")
    sizeGroup:SetPoint("TOPLEFT", posGroup, "BOTTOMLEFT", 0, -12)
    sizeGroup:SetSize(440, 80)

    local fontSlider = Jui.UI:CreateSlider(sizeGroup, "Font Size", 8, 20,
        function() return db.size end,
        function(v) db.size = v; RefreshJuiWinrates() end)
    fontSlider:SetPoint("TOPLEFT", 15, sizeGroup.ContentTop)

    parent:SetHeight(190)
end

Jui.UI.Settings:RegisterModulePage("winrate", "Winrate", "gameplay")
