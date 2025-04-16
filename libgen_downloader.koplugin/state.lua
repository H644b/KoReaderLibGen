-- state.lua
-- Manages the plugin's internal state

local logger = require("logger")

local State = {
    -- UI State
    current_view = "search", -- "search", "results", "details", "downloading", "alternatives"
    search_query = "",
    search_section = "fiction", -- "fiction" or "scitech"
    status_message = "",
    is_loading = false,
    loader_message = "",

    -- Search Results State
    search_results = {}, -- Array of entry tables {id=..., title=..., ...}
    current_page = 1,
    selected_result_index = 1,
    has_more_results = false,

    -- Detail View State
    detailed_entry = nil, -- The entry table currently being viewed
    alternative_links = {}, -- Array of alternative download URLs for detailed_entry

    -- Download State (Simplified - A real app might need more complex queue mgmt)
    -- Map of { entry_id = { entry=entry_table, progress=0..1, total_bytes=int, current_bytes=int, status="queued/downloading/failed/done", filename=str } }
    downloads = {},
}

-- Reset state specific to search results
function State:reset_search()
    self.search_results = {}
    self.current_page = 1
    self.selected_result_index = 1
    self.has_more_results = false
    self.detailed_entry = nil
    self.alternative_links = {}
    self.current_view = "search" -- Go back to search view
    logger.dbg("State: Search state reset")
end

-- Update loading state and message
function State:set_loading(loading, message)
    self.is_loading = loading
    self.loader_message = message or ""
    logger.dbg("State: Loading set to", loading, message and ("with message: "..message) or "")
    -- NOTE: UI update needs to be triggered externally after calling this
end

-- Update status message
function State:set_status(message)
    self.status_message = message or ""
     logger.info("State: Status set to", message)
    -- NOTE: UI update needs to be triggered externally
end

-- Update search results and related state
function State:set_search_results(results, page)
    self.search_results = results or {}
    self.current_page = page or 1
    self.selected_result_index = 1 -- Reset selection on new results
    -- Estimate based on typical LibGen page size (e.g., 25)
    self.has_more_results = #self.search_results >= 25
    self.current_view = "results" -- Switch view
    logger.info("State: Search results updated for page", self.current_page, "Count:", #self.search_results)
    -- NOTE: UI update needs to be triggered externally
end

-- Set the entry for the detail view
function State:set_detailed_entry(entry)
    self.detailed_entry = entry
    self.alternative_links = {} -- Clear old alternative links
    self.current_view = entry and "details" or "results" -- Go to details if entry provided, else back to results
    logger.info("State: Detailed entry set to", entry and entry.id or "nil")
    -- NOTE: UI update needs to be triggered externally
end

-- Set alternative links for the current detailed entry
function State:set_alternative_links(links)
    if self.current_view ~= "details" or not self.detailed_entry then
        logger.warn("State: Tried to set alternative links without a detailed entry view.")
        return
    end
    self.alternative_links = links or {}
    logger.info("State: Alternative links updated for", self.detailed_entry.id, "Count:", #self.alternative_links)
    -- NOTE: UI update needs to be triggered externally (e.g., refresh detail view)
end

-- Add an entry to the download status map (or update existing)
function State:add_or_update_download(entry_id, entry_data, download_info)
    self.downloads[entry_id] = self.downloads[entry_id] or {}
    self.downloads[entry_id].entry = entry_data or self.downloads[entry_id].entry -- Store entry details
    for k, v in pairs(download_info) do
        self.downloads[entry_id][k] = v
    end
     logger.dbg("State: Download updated for", entry_id, "Status:", download_info.status)
    -- NOTE: UI update needs to be triggered externally
end


logger.info("State module loaded.")
return State
