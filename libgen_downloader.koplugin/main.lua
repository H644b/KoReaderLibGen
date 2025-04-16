-- main.lua
-- Main plugin logic, menu registration, initialization

local Device = require("device")
local Screen = Device.screen -- Get screen early
local UIManager = require("ui/uimanager")
local Menu = require("ui/menu")
local _ = require("gettext") -- For localization if needed later
local logger = require("logger")

-- Require our plugin modules (use pcall for safety during development)
local ok_config, Config = pcall(require, "config")
local ok_api, LibgenAPI = pcall(require, "libgen_api")
local ok_ui, UI = pcall(require, "ui")
local ok_state, State = pcall(require, "state") -- State might initialize itself

if not (ok_config and ok_api and ok_ui and ok_state) then
    logger.error("Failed to load one or more LibgenDownloader modules:",
                 "Config:", ok_config and "OK" or Config,
                 "API:", ok_api and "OK" or LibgenAPI,
                 "UI:", ok_ui and "OK" or UI,
                 "State:", ok_state and "OK" or State)
    -- Consider showing an error to the user here as well
    return nil -- Stop plugin initialization
end


local LibgenDownloader = {}

-- Function called when the plugin menu item is tapped
function LibgenDownloader:_showSearchDialog() -- Renamed to avoid conflict with potential widget methods
    -- Initialize config if not already done
    if not Config:is_config_loaded() then
        -- Show loading indicator before starting async operation
        UIManager:showInfoMessage(_("Loading LibGen Config..."))
        Config:fetch_config(function(success, err_msg)
            -- Hide loading indicator
            UIManager:closeInfoMessage() -- Assuming this closes the message
            if success then
                 -- Config loaded, now find mirror
                 self:_findMirrorAndShowUI()
            else
                UIManager:showError(_("LibGen Config Error"), err_msg or _("Failed to load configuration."))
            end
        end)
    else
        -- Config already loaded, just ensure mirror is selected
        self:_findMirrorAndShowUI()
    end
end

-- Helper to find mirror and then show the main UI
function LibgenDownloader:_findMirrorAndShowUI()
     if Config.mirror and Config.mirror ~= "" then -- Check if mirror already found
          logger.info("Using previously found mirror:", Config.mirror)
          UI:showMainDialog()
          return
     end

     UIManager:showInfoMessage(_("Finding working LibGen mirror..."))
     Config:find_working_mirror(function(mirror, err_msg)
         UIManager:closeInfoMessage()
         if mirror then
             Config.mirror = mirror -- Store the working mirror (might need better state mgmt)
             UI:showMainDialog()
         else
             UIManager:showError(_("LibGen Mirror Error"), err_msg or _("Could not find a working mirror."))
         end
     end)
end

-- Function to register the plugin in KOReader's Tools menu
function LibgenDownloader:registerPluginMenu(menu_container)
    logger.dbg("LibgenDownloader: Attempting to register plugin menu")
    -- Check if menu_container and registerItem are valid
    if not (menu_container and menu_container.registerItem) then
        logger.warn("LibgenDownloader: Invalid menu container passed to registerPluginMenu")
        return false
    end

    -- Use dispatcher from UIManager, safer than assuming menu_container has it
    local dispatcher = UIManager

    local plugin_menu = Menu:new{
        width = Screen:scaleByDPI(220), -- Increased width slightly
        height = Screen:scaleByDPI(40), -- Increased height slightly
        cancellable = true,
        show_parent = menu_container,
        dispatcher = dispatcher, -- Use UIManager's dispatcher
    }

    plugin_menu:registerItem{
        text = _("Search LibGen"),
        callback = function()
            -- Close the parent menu first
            if menu_container.closeMenu then
                 menu_container:closeMenu(plugin_menu) -- Close the sub-menu
                 if menu_container.parent_menu and menu_container.parent_menu.closeMenu then
                     menu_container.parent_menu:closeMenu(menu_container) -- Close the main menu item
                 end
             elseif menu_container.clearMenuTable then -- Fallback for older structures
                 menu_container:clearMenuTable()
             end

             -- Schedule the dialog showing to avoid UI conflicts
            dispatcher:scheduleIn(function() self:_showSearchDialog() end, 0.05)
        end,
    }

    menu_container:registerItem{
        text = _("LibGen Downloader"), -- Text for the main menu entry
        sub_item_table = plugin_menu,
        priority = 150, -- Adjust priority to position in Tools menu
    }

    logger.info("LibgenDownloader: Plugin menu registered successfully")
    return true -- Indicate success
end


-- Plugin initialization
function LibgenDownloader:init()
    logger.info("LibgenDownloader plugin initializing...")
    -- Can preload config here if desired, but might slow down startup
    -- Config:fetch_config()
end

logger.info("LibgenDownloader main.lua loaded.")
return LibgenDownloader
