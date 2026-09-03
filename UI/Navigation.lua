--[[
    UI/Navigation.lua
    ---------------------------------------------------------------------
    The sidebar (section 32 of the spec): grouped into Dashboard / Core /
    Gameplay / Auras rather than one flat row of equal tabs. Pages
    register themselves here the same way modules register with
    Jui:RegisterModule - UI/Overview.lua, UI/Settings.lua (for the
    Interface page) and each module's CreateSettings all call
    Jui.UI.Navigation:AddPage() to appear in the list.
--]]

local addonName, ns = ...

Jui = Jui or {}
Jui.UI = Jui.UI or {}
Jui.UI.Navigation = {}

local C = Jui.Theme
local Nav = Jui.UI.Navigation

local GROUPS = {
    {key = "dashboard", label = "Dashboard"},
    {key = "core",      label = "Core"},
    {key = "gameplay",  label = "Gameplay"},
    {key = "auras",     label = "Auras"},
}

local pages = {}      -- [id] = {label, group, buildFn}
local pageOrder = {}
local buttons = {}    -- [id] = button
local activeId = nil
local sidebar, content
local scrollFrame      -- persistent; only its scroll CHILD gets rebuilt per page
local recycleBin       -- hidden parking spot for a previous page's leftovers

-- Main(900) - PAD*2(28) - SIDEBAR_WIDTH(170) - SIDEBAR_GAP(8) - the scroll
-- frame's own 24px inset (see ShowPage below), matching UI/Main.lua's
-- layout constants. Computed here rather than queried live via
-- scrollFrame:GetWidth() at scroll-child-creation time: that query isn't
-- guaranteed to run after the scroll frame's own anchor-based geometry has
-- resolved, and if it read back 0 (or anything narrower than a page's real
-- content), anything positioned past that edge - like Capping's Test
-- Display button, which sits to the right of its card - would get
-- silently clipped, since a scroll frame clips to its child's own width,
-- not just its own viewport.
local SCROLL_CHILD_WIDTH = 670

-- group: "dashboard" | "core" | "gameplay" | "auras"
-- buildFn(parent) runs fresh every time this page is opened, into a new
-- scroll child - see ShowPage below. Tall pages (Raid Auras especially)
-- need this to actually be a scroll frame, not a plain fixed-height frame:
-- the window itself doesn't grow to fit content the way the pre-1.0
-- addon's did, so anything taller than the window needs to scroll rather
-- than just render past the bottom edge.
function Nav:AddPage(id, label, group, buildFn)
    pages[id] = {label = label, group = group, buildFn = buildFn}
    table.insert(pageOrder, id)
end

local function ShowPage(id)
    local page = pages[id]
    if not page then return end

    -- The previous page's scroll child is fully detached (reparented to a
    -- hidden recycling frame) rather than reused, for the same reason the
    -- last fix removed frame-caching entirely: a single container that's
    -- providably empty before each rebuild can't end up with old content
    -- still attached to anything visible.
    local oldChild = scrollFrame:GetScrollChild()
    if oldChild then
        oldChild:Hide()
        oldChild:SetParent(recycleBin)
    end

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(SCROLL_CHILD_WIDTH)
    scrollChild:SetHeight(1) -- buildFn is expected to grow this to fit its own content
    scrollFrame:SetScrollChild(scrollChild)
    scrollFrame:SetVerticalScroll(0)

    -- Wrapped in pcall: if buildFn errors partway through (WoW hides Lua
    -- errors by default, so this could otherwise fail completely
    -- silently), the page shows the error instead of a mysteriously
    -- truncated layout, AND - critically - the button-highlighting below
    -- still runs regardless. Before this fix, an error here would abort
    -- the rest of ShowPage entirely, leaving the sidebar's active-tab
    -- highlight stuck on whatever page was shown last, out of sync with
    -- whatever partial content did make it onto screen.
    local ok, err = pcall(page.buildFn, scrollChild)
    if not ok then
        local errorText = Jui.UI:CreateText(scrollChild, "Small", C.textFaint)
        errorText:SetPoint("TOPLEFT", 4, -4)
        errorText:SetPoint("RIGHT", -4, 0)
        errorText:SetJustifyH("LEFT")
        errorText:SetText("|cffff6b6bThis page failed to build:|r\n" .. tostring(err))
        scrollChild:SetHeight(math.max(errorText:GetStringHeight() + 20, 60))
        geterrorhandler()(err)
    end

    if buttons[activeId] then buttons[activeId]:SetActive(false) end
    if buttons[id] then buttons[id]:SetActive(true) end
    activeId = id
end
Nav.ShowPage = ShowPage

local function CreateNavButton(parent, label)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(28)

    local accent = btn:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMLEFT", 0, 0)
    accent:SetWidth(2)
    accent:SetColorTexture(unpack(C.accent))
    accent:Hide()

    btn.Text = Jui.UI:CreateText(btn, "Small", C.textSecond)
    btn.Text:SetPoint("LEFT", 12, 0)
    btn.Text:SetText(label)

    function btn:SetActive(active)
        self.isActive = active
        if active then
            accent:Show()
            self.Text:SetTextColor(unpack(C.textPrimary))
        else
            accent:Hide()
            self.Text:SetTextColor(unpack(C.textSecond))
        end
    end

    btn:SetScript("OnEnter", function(self)
        if not self.isActive then self.Text:SetTextColor(unpack(C.textPrimary)) end
    end)
    btn:SetScript("OnLeave", function(self)
        if not self.isActive then self.Text:SetTextColor(unpack(C.textSecond)) end
    end)

    return btn
end

function Nav:Initialize(sidebarFrame, contentFrame)
    sidebar, content = sidebarFrame, contentFrame

    -- The scrollbar itself is hidden (per this addon's established visual
    -- style) but the template's mouse-wheel handler still works.
    scrollFrame = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 12, -12)
    scrollFrame:SetPoint("BOTTOMRIGHT", -12, 12)
    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:Hide()
        scrollBar:SetScript("OnShow", scrollBar.Hide)
    end

    -- Never shown - just holds a previous page's discarded widgets so
    -- they're fully detached from the live scroll frame rather than
    -- destroyed (WoW frames can't actually be destroyed, only
    -- hidden/reparented).
    recycleBin = CreateFrame("Frame", nil, UIParent)
    recycleBin:Hide()

    local y = -10
    for _, groupDef in ipairs(GROUPS) do
        local groupPages = {}
        for _, id in ipairs(pageOrder) do
            if pages[id].group == groupDef.key then
                table.insert(groupPages, id)
            end
        end
        if #groupPages > 0 then
            if groupDef.key ~= "dashboard" then
                -- Deliberately styled to read as a section label, not
                -- another row in the button list: a size smaller than any
                -- real button text uses, a thin divider directly under it,
                -- and no accent bar / hover state / active state of any
                -- kind, since it isn't clickable.
                local heading = sidebar:CreateFontString(nil, "OVERLAY")
                heading:SetPoint("TOPLEFT", 12, y)
                Jui.Fonts:Apply(heading, 9)
                heading:SetTextColor(unpack(C.textFaint))
                heading:SetText(groupDef.label:upper())

                local headingLine = Jui.UI:CreateDivider(sidebar)
                headingLine:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -4)
                headingLine:SetPoint("RIGHT", -12, 0)

                y = y - 22
            end

            for _, id in ipairs(groupPages) do
                local btn = CreateNavButton(sidebar, pages[id].label)
                btn:SetPoint("TOPLEFT", 0, y)
                btn:SetPoint("RIGHT", 0, 0)
                btn:SetScript("OnClick", function() ShowPage(id) end)
                buttons[id] = btn
                y = y - 28
            end
            y = y - 10
        end
    end

    if pageOrder[1] then
        ShowPage(pageOrder[1])
    end
end
