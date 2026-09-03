--[[
    Core/Commands.lua
    ---------------------------------------------------------------------
    One public command: /jui. Everything else the old addon had
    (/juicapping test, /juicapping lock, /jcap, /lg) is either gone or
    moved into the UI itself - a settings window shouldn't need its own
    parallel command-line interface.
--]]

local addonName, ns = ...

SLASH_JUI1 = "/jui"
SlashCmdList["JUI"] = function()
    if not Jui.UI or not Jui.UI.Main then return end
    if Jui.UI.Main:IsShown() then
        Jui.UI.Main:Hide()
    else
        Jui.UI.Main:Show()
    end
end
