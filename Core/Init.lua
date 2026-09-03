--[[
    Core/Init.lua
    ---------------------------------------------------------------------
    The addon's entry point. Everything else (Database, Events, Modules,
    UI, and every individual module) only registers itself when its file
    loads - nothing actually runs until this file's ADDON_LOADED handler
    fires and walks through a fixed, predictable order:

        ADDON_LOADED
            -> Database:Initialize()   (JuiDB is ready)
            -> Modules:InitializeAll() (every module reaches its saved state)
            -> UI:Initialize()         (the window exists, built on real data)

    Nothing before this point should assume JuiDB, or any other module,
    already exists.
--]]

local addonName, ns = ...

Jui = Jui or {}
Jui.version = "1.0.2"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, loadedAddon)
    if loadedAddon ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")

    Jui.Database:Initialize()
    Jui.Theme:ApplySavedAccent()
    Jui.Modules:InitializeAll()
    if Jui.UI then Jui.UI:Initialize() end

    print("|cffffd100Jui:|r v" .. Jui.version .. " loaded. Type /jui to open.")
end)
