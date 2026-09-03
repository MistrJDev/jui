--[[
    UI/Main.lua
    ---------------------------------------------------------------------
    The window itself: a sidebar (built by UI/Navigation.lua) on the left,
    a content area on the right, opened/closed with /jui or the in-game
    Escape key like a normal Blizzard panel. Jui.UI:Initialize() is called
    once from Core/Init.lua's lifecycle, after the database and every
    module are already in their final startup state - so nothing built
    here has to guess at incomplete data.
--]]

local addonName, ns = ...

Jui = Jui or {}
Jui.UI = Jui.UI or {}

local C = Jui.Theme

local PAD = 14
local HEADER_HEIGHT = 34
local SIDEBAR_WIDTH = 170

function Jui.UI:Initialize()
    local Main = Jui.UI:CreatePanel(UIParent, C.bgWindow, C.border, 1)
    Main:SetSize(900, 560)
    Main:SetPoint("CENTER")
    Main:SetFrameStrata("MEDIUM")
    Main:SetMovable(true)
    Main:EnableMouse(true)
    Main:EnableKeyboard(true)
    Main:SetClampedToScreen(true)
    Main:RegisterForDrag("LeftButton")
    Main:SetScript("OnDragStart", Main.StartMoving)
    Main:SetScript("OnDragStop", Main.StopMovingOrSizing)
    Main:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    Main:Hide()
    Jui.UI.Main = Main

    -- Standard Blizzard panel behavior: closing with Escape works like any
    -- other UI panel, in addition to the in-frame close button and /jui.
    -- UISpecialFrames looks the frame up by its GLOBAL name, so Main needs
    -- one - but it must NOT be "Jui", since that's the addon's own
    -- namespace table (Jui.UI, Jui.Fonts, Jui.Database, ...). Using the
    -- same name here overwrote that entire global table with this Frame
    -- object mid-initialization, breaking every Jui.* reference for the
    -- rest of the session (both crash reports trace back to exactly this).
    tinsert(UISpecialFrames, "JuiMainFrame")
    _G["JuiMainFrame"] = Main

    -- Header
    local header = CreateFrame("Frame", nil, Main)
    header:SetPoint("TOPLEFT", PAD, -PAD)
    header:SetPoint("TOPRIGHT", -PAD, -PAD)
    header:SetHeight(HEADER_HEIGHT)

    local title = Jui.UI:CreateText(header, "Header", C.accent)
    title:SetPoint("LEFT", 2, 0)
    title:SetText("Jui")

    local version = Jui.UI:CreateText(header, "Small", C.textFaint)
    version:SetPoint("LEFT", title, "RIGHT", 8, -1)
    version:SetText("v" .. Jui.version)

    local close = CreateFrame("Button", nil, header)
    close:SetSize(20, 20)
    close:SetPoint("RIGHT", -2, 0)
    close.Text = Jui.UI:CreateText(close, "Header", C.textSecond)
    close.Text:SetAllPoints()
    close.Text:SetJustifyH("CENTER")
    close.Text:SetText("\195\151") -- ×
    close:SetScript("OnEnter", function() close.Text:SetTextColor(unpack(C.danger)) end)
    close:SetScript("OnLeave", function() close.Text:SetTextColor(unpack(C.textSecond)) end)
    close:SetScript("OnClick", function() Main:Hide() end)

    local headerLine = Jui.UI:CreateDivider(Main)
    headerLine:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
    headerLine:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -10)

    -- Sidebar + Content
    local sidebar = Jui.UI:CreatePanel(Main, C.bgPanel, C.borderSoft, 1)
    sidebar:SetPoint("TOPLEFT", headerLine, "BOTTOMLEFT", 0, -8)
    sidebar:SetPoint("BOTTOMLEFT", PAD, PAD)
    sidebar:SetWidth(SIDEBAR_WIDTH)
    Jui.UI.Sidebar = sidebar

    local content = Jui.UI:CreatePanel(Main, C.bgPanel, C.borderSoft, 1)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 8, 0)
    content:SetPoint("BOTTOMRIGHT", Main, "BOTTOMRIGHT", -PAD, PAD)
    Jui.UI.Content = content

    -- Scale is applied once here and again live whenever the Interface
    -- page's scale slider changes.
    Main:SetScale(Jui.Database:Get().profile.scale or 1)

    Jui.UI.Navigation:Initialize(sidebar, content)
end

-- Called from the Interface page's Scale slider.
function Jui.UI:ApplyScale()
    local db = Jui.Database:Get()
    self.Main:SetScale(db.profile.scale or 1)
end
