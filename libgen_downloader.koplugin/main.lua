-- config.lua
-- Handles fetching, storing, and providing configuration

-- Use pcall for safety, especially during development or optional dependencies
local ok_network, Network = pcall(require, "network")
local ok_json, JSON = pcall(require, "vendor.dkjson") -- Assumes dkjson is bundled
local ok_storage, DataStorage = pcall(require, "datastorage") -- For caching
local ok_ui, UIManager = pcall(require, "ui/uimanager") -- For scheduling mirror checks

if not (ok_network and ok_json and ok_storage and ok_ui) then
    error("LibGen Config: Failed to load dependencies -"..
          " Network:"..(ok_network or Network)..
          " JSON:"..(ok_json or JSON)..
          " Storage:"..(ok_storage or DataStorage)..
          " UI:"..(ok_ui or UIManager))
    return nil
end

local logger = require("logger")


local Config = {
    _url = "https://raw.githubusercontent.com/H644b/libgen-downloader-fiction/configuration/config.json", -- Your config URL
    _cache_key = "libgen_downloader_config_v2", -- Increment version if format changes
    _cache_duration_hours = 12, -- Cache duration
    _loaded_config = nil,
    _is_loading = false,
    mirror = nil, -- Holds the currently selected working mirror
    _default_config = {
        latestVersion = "0.0.0",
        mirrors = {"http://libgen.is", "http://libgen.rs", "http://libgen.st"}, -- Basic fallback mirrors
        searchReqPattern = "{mirror}/search.php?req={query}&lg_topic=libgen&open=0&view=simple&res=25&phrase=1&column=def&page={pageNumber}",
        fictionSearchReqPattern = "{mirror}/fiction/?q={query}",
        searchByMD5Pattern = "{mirror}/search.php?req={md5}&column=md5",
        MD5ReqPattern = "{mirror}/json.php?ids={id}&fields=md5",
        columnFilterQueryParamKey = "column",
        columnFilterQueryParamValues = {},
    }
}

function Config:is_config_loaded()
    return self._loaded_config ~= nil
end

function Config:fetch_config(callback)
    if self._is_loading then
        logger.dbg("LibGen Config: Fetch already in progress.")
        return
    end
    self._is_loading = true
    logger.info("LibGen Config: Starting config fetch process...")

    -- Try loading from cache first
    local cached_config_wrapper = DataStorage:readSettings(self._cache_key)
    if cached_config_wrapper and cached_config_wrapper.timestamp and cached_config_wrapper.data and
       (os.time() - cached_config_wrapper.timestamp < self._cache_duration_hours * 3600) then
        logger.info("LibGen Config: Using valid cached config.")
        self._loaded_config = cached_config_wrapper.data
        self.mirror = cached_config_wrapper.mirror or nil -- Load cached mirror too
        self._is_loading = false
        if callback then callback(true) end
        return
    end

    logger.info("LibGen Config: No valid cache, fetching fresh config from", self._url)
    Network:http_get(self._url, function(success, body, err_msg)
        if success and body then
            local ok, config_data = pcall(JSON.decode, body)
            if ok and type(config_data) == "table" then
                logger.info("LibGen Config: Successfully fetched and parsed.")
                self._loaded_config = self:_merge_defaults(config_data)

                -- Save to cache (without mirror initially, find that separately)
                DataStorage:saveSettings(self._cache_key, {
                    timestamp = os.time(),
                    data = self._loaded_config,
                    mirror = nil -- Mirror will be saved after successful findMirror
                })

                self._is_loading = false
                if callback then callback(true) end -- Indicate config data loaded
            else
                local parse_err = config_data -- pcall returns error message on failure
                logger.error("LibGen Config: Failed to parse JSON -", parse_err)
                logger.warn("LibGen Config: Using default config due to parse error.")
                self._loaded_config = self._default_config
                self._is_loading = false
                if callback then callback(false, "Failed to parse config JSON: " .. tostring(parse_err)) end
            end
        else
            logger.error("LibGen Config: Failed to fetch -", err_msg)
            logger.warn("LibGen Config: Using default config due to fetch error.")
            self._loaded_config = self._default_config
            self._is_loading = false
            if callback then callback(false, "Failed to fetch config: " .. tostring(err_msg)) end
        end
    end)
end

-- Simple merge, fetched values override defaults
function Config:_merge_defaults(fetched_config)
    local merged = {}
    -- Start with defaults
    for k, v in pairs(self._default_config) do
        merged[k] = v
    end
    -- Override with fetched values if they exist and match type (basic check)
    for k, fetched_v in pairs(fetched_config) do
         if self._default_config[k] ~= nil and type(fetched_v) == type(self._default_config[k]) then
             merged[k] = fetched_v
         elseif self._default_config[k] == nil then -- Add keys not in default
            merged[k] = fetched_v
         end
    end
    return merged
end


function Config:get_config()
    if not self:is_config_loaded() then
        logger.warn("Accessing LibGen config before loaded, returning defaults.")
        return self._default_config
    end
    return self._loaded_config
end

function Config:find_working_mirror(callback)
    local config = self:get_config()
    if not config or not config.mirrors or #config.mirrors == 0 then
        logger.error("LibGen Config: No mirrors available to test.")
        if callback then callback(nil, "No mirrors defined in config") end
        return
    end

    local mirrors_to_test = config.mirrors
    local current_index = 1
    local working_mirror = nil

    local function test_next_mirror()
        if current_index > #mirrors_to_test then
            logger.error("LibGen Config: Exhausted all mirrors, none working.")
            if callback then callback(nil, "Could not find a working mirror") end
            return
        end

        local mirror_url = mirrors_to_test[current_index]

        -- Basic validation of mirror URL format
        if not (type(mirror_url) == "string" and mirror_url:match("^https?://")) then
             logger.warn("LibGen Config: Skipping invalid mirror URL format:", mirror_url)
             current_index = current_index + 1
             UIManager:scheduleIn(test_next_mirror, 0.01) -- Try next immediately
             return
        end

        logger.info("LibGen Config: Testing mirror", current_index, "/", #mirrors_to_test, ":", mirror_url)

        -- Use HEAD request for faster check, increase timeout slightly
        Network:http_request("HEAD", mirror_url, nil, {timeout_secs = 7}, function(success, headers, err_msg)
            if success then
                logger.info("LibGen Config: Found working mirror:", mirror_url)
                working_mirror = mirror_url
                self.mirror = working_mirror -- Store it globally in Config module

                -- Update cache with the working mirror
                local cached_config_wrapper = DataStorage:readSettings(self._cache_key)
                if cached_config_wrapper and cached_config_wrapper.data then
                    cached_config_wrapper.mirror = working_mirror
                    cached_config_wrapper.timestamp = os.time() -- Update timestamp too
                    DataStorage:saveSettings(self._cache_key, cached_config_wrapper)
                end

                if callback then callback(working_mirror) end
            else
                logger.warn("LibGen Config: Mirror failed:", mirror_url, "-", err_msg)
                current_index = current_index + 1
                -- Test next mirror asynchronously
                UIManager:scheduleIn(test_next_mirror, 0.05) -- Small delay before next try
            end
        end)
    end

    -- Start testing the first mirror
    test_next_mirror()
end


return Config
