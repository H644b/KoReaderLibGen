-- init.lua
-- Entry point required by KOReader

local logger = require("logger")

-- Use pcall for safety, especially during development
local ok, main_module = pcall(require, "main")

if not ok then
    logger.error("Failed to load LibgenDownloader main module:", main_module)
    -- Show an error to the user if possible/appropriate
    local UIManager = require("ui/uimanager")
    if UIManager then
        UIManager:showError("Plugin Load Error", "Failed to load LibGen Downloader plugin main module.\n" .. tostring(main_module))
    end
    return nil -- Prevent plugin from loading further
end

logger.info("LibgenDownloader init.lua finished.")
return main_module
