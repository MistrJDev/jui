--[[
    UI/Overview.lua
    ---------------------------------------------------------------------
    The dashboard (sections 14/33 of the spec): one card per registered
    module, each showing its status and jumping straight to that module's
    settings page - rather than the old flat list of description rows.
--]]

local addonName, ns = ...

Jui = Jui or {}
Jui.UI = Jui.UI or {}

local C = Jui.Theme

local CARD_WIDTH, CARD_HEIGHT = 300, 92
local CARD_GAP = 12

local function CreateModuleCard(parent, def)
    local card = Jui.UI:CreatePanel(parent, C.bgCard, C.borderSoft, 1)
    card:SetSize(CARD_WIDTH, CARD_HEIGHT)

    local name = Jui.UI:CreateText(card, "Body", C.textPrimary)
    name:SetPoint("TOPLEFT", 12, -10)
    name:SetText(def.name:upper())

    local status = Jui.UI:CreateStatus(card, Jui.Modules:IsEnabled(def.id))
    status:SetPoint("TOPRIGHT", -12, -12)

    local desc = Jui.UI:CreateText(card, "Small", C.textFaint)
    desc:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -6)
    desc:SetPoint("RIGHT", -12, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText(def.description or "")

    local openBtn = Jui.UI:CreateButton(card, "Configure \226\134\146")
    openBtn:SetSize(100, 22)
    openBtn:SetPoint("BOTTOMRIGHT", -10, 10)
    openBtn:SetScript("OnClick", function()
        Jui.UI.Navigation.ShowPage(def.id)
    end)

    card.RefreshStatus = function() status:SetOn(Jui.Modules:IsEnabled(def.id)) end

    return card
end

Jui.UI.Navigation:AddPage("overview", "Overview", "dashboard", function(parent)
    local greeting = Jui.UI:CreateText(parent, "Title", C.textPrimary)
    greeting:SetPoint("TOPLEFT", 0, 0)
    greeting:SetPoint("RIGHT", 0, 0)
    greeting:SetJustifyH("LEFT")
    greeting:SetText("Welcome to Jui")

    local sub = Jui.UI:CreateText(parent, "Small", C.textFaint)
    sub:SetPoint("TOPLEFT", greeting, "BOTTOMLEFT", 0, -4)
    sub:SetPoint("RIGHT", 0, 0)
    sub:SetJustifyH("LEFT")
    sub:SetText(UnitName("player") and ("Logged in as " .. UnitName("player")) or "Your addon configuration")

    -- cardArea is NOT stretched down to parent's bottom - parent is now a
    -- scroll child that needs to be sized to fit ITS content, so nothing
    -- inside this page can size itself off of parent's (currently
    -- unknown, effectively 1px) height without becoming circular.
    local cardArea = CreateFrame("Frame", nil, parent)
    cardArea:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -16)
    cardArea:SetPoint("RIGHT", 0, 0)

    local col, row = 0, 0
    local cols = 2
    local moduleCount = 0
    for _, def in ipairs(Jui.Modules:GetAll()) do
        local card = CreateModuleCard(cardArea, def)
        card:SetPoint("TOPLEFT", col * (CARD_WIDTH + CARD_GAP), -row * (CARD_HEIGHT + CARD_GAP))
        col = col + 1
        moduleCount = moduleCount + 1
        if col >= cols then
            col = 0
            row = row + 1
        end
    end

    local rows = math.ceil(moduleCount / cols)
    cardArea:SetHeight(rows * CARD_HEIGHT + math.max(rows - 1, 0) * CARD_GAP)

    -- parent's total height = everything above cardArea (greeting + sub +
    -- the 16px gap) plus cardArea's own height, which is what actually
    -- drives the scroll range.
    local headerHeight = greeting:GetStringHeight() + 4 + sub:GetStringHeight() + 16
    parent:SetHeight(headerHeight + cardArea:GetHeight())
end)
