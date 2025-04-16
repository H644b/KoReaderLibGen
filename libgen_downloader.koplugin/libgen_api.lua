-- libgen_api.lua
-- Handles interactions with LibGen (searching, getting download links)

local ok_config, Config = pcall(require, "config")
local ok_network, Network = pcall(require, "network")
local ok_parser, HTMLParser = pcall(require, "html_parser")
local ok_url, Url = pcall(require, "socket.url") -- For URL encoding

if not (ok_config and ok_network and ok_parser and ok_url) then
    error("LibgenAPI: Failed to load dependencies -"..
          " Config:"..(ok_config or Config)..
          " Network:"..(ok_network or Network)..
          " Parser:"..(ok_parser or HTMLParser)..
          " Url:"..(ok_url or Url))
    return nil
end

local logger = require("logger")

local LibgenAPI = {}

-- callback(success_boolean, entries_table_or_nil, error_message_or_nil)
function LibgenAPI:search(query, page, section, selected_filter_value, callback)
    logger.info(string.format("LibgenAPI: Searching section '%s' for '%s', page %d", section, query, page))
    local config_data = Config:get_config()
    local base_mirror = Config.mirror -- Use the globally stored working mirror

    if not base_mirror or base_mirror == "" then
        logger.error("LibgenAPI Search: No working mirror available.")
        if callback then callback(false, nil, "No working mirror configured") end
        return
    end

    -- Construct search URL using Lua string formatting/replacement
    local pattern = section == "fiction" and config_data.fictionSearchReqPattern or config_data.searchReqPattern
    if not pattern then
        logger.error("LibgenAPI Search: No search pattern found in config for section:", section)
        if callback then callback(false, nil, "Search pattern missing for section: " .. section) end
        return
    end

    local url = pattern:gsub("{mirror}", base_mirror)
                     :gsub("{query}", Url.escape(query)) -- URL Encode query
                     :gsub("{pageNumber}", tostring(page))
                     :gsub("{pageSize}", "25") -- Page size might only apply to scitech

    -- Add page param for fiction if needed (URL pattern might already include it)
    if section == "fiction" and page > 1 and not url:find("[?&]page=", 1, true) then
        url = url .. (url:find("?", 1, true) and "&" or "?") .. "page=" .. tostring(page)
    end

    -- Add column filter for SciTech if needed
    if section == "scitech" and selected_filter_value then
        local key = config_data.columnFilterQueryParamKey or "column"
        url = url .. "&" .. key .. "=" .. Url.escape(selected_filter_value)
    end

    logger.dbg("LibgenAPI Search URL:", url)

    Network:http_get(url, function(success, html_content, err_msg)
        if success and html_content then
            logger.dbg("LibgenAPI Search: Received HTML content, parsing...")
            local entries
            local parse_ok = false
            if section == "fiction" then
                entries = HTMLParser:parse_search_results_fiction(html_content, base_mirror) -- Pass base_mirror
            else -- scitech
                entries = HTMLParser:parse_search_results_scitech(html_content)
            end

            if entries then -- Check if parsing returned a table (even if empty)
                logger.info("LibgenAPI Search: Parsing successful, entries found:", #entries)
                if callback then callback(true, entries) end
            else
                 logger.error("LibgenAPI Search: Failed to parse search results HTML.")
                if callback then callback(false, nil, "Failed to parse search results") end
            end
        else
            logger.error("LibgenAPI Search: Failed to fetch search results -", err_msg)
            if callback then callback(false, nil, "Failed to fetch search results: " .. tostring(err_msg)) end
        end
    end)
end


-- Gets the final download links for an entry
-- callback(success_boolean, links_table_or_nil, error_message_or_nil)
function LibgenAPI:get_download_links(entry, callback)
    logger.info("LibgenAPI: Getting download links for entry ID:", entry and entry.id or "N/A")
    if not entry or not entry.mirror or not entry.mirror:match("^https?://") then
        logger.error("LibgenAPI: Invalid entry or mirror link provided:", entry and entry.mirror or "N/A")
        if callback then callback(false, nil, "Invalid entry or missing/invalid mirror link") end
        return
    end

    local function fetch_and_parse_final_page(download_page_url)
        logger.dbg("LibgenAPI: Fetching final download page:", download_page_url)
        Network:http_get(download_page_url, function(success, html_content, err_msg)
            if success and html_content then
                local links = HTMLParser:parse_download_page_links(html_content)
                if links then
                    logger.info("LibgenAPI: Found download links:", table.concat(links, ", "))
                    if callback then callback(true, links) end
                else
                    logger.error("LibgenAPI: Failed to parse download links from final page:", download_page_url)
                    if callback then callback(false, nil, "Failed to parse download links from final page") end
                end
            else
                logger.error("LibgenAPI: Failed to fetch final download page:", download_page_url, "-", err_msg)
                if callback then callback(false, nil, "Failed to fetch final download page: " .. tostring(err_msg)) end
            end
        end)
    end

    -- Determine if it's likely a fiction entry based on mirror URL structure or entry type marker
    local is_fiction = entry.type == "fiction" or entry.mirror:find("/fiction/", 1, true)

    if is_fiction then
        -- Fiction: Fetch detail page -> Parse for download page link -> Fetch download page -> Parse links
        logger.dbg("LibgenAPI: Fetching fiction detail page:", entry.mirror)
        Network:http_get(entry.mirror, function(success, detail_html, err_msg)
            if success and detail_html then
                local download_page_link = HTMLParser:parse_fiction_detail_page_link(detail_html)
                if download_page_link then
                    logger.info("LibgenAPI: Found intermediate download page link:", download_page_link)
                    fetch_and_parse_final_page(download_page_link)
                else
                    logger.error("LibgenAPI: Failed to find intermediate download page link on fiction detail page:", entry.mirror)
                    if callback then callback(false, nil, "Failed to find download page link on fiction detail page") end
                end
            else
                logger.error("LibgenAPI: Failed to fetch fiction detail page:", entry.mirror, "-", err_msg)
                if callback then callback(false, nil, "Failed to fetch fiction detail page: " .. tostring(err_msg)) end
            end
        end)
    else
        -- SciTech: Directly fetch the mirror URL (which should be the download page) -> Parse links
        logger.dbg("LibgenAPI: Assuming Sci-Tech, fetching download page directly:", entry.mirror)
        fetch_and_parse_final_page(entry.mirror)
    end
end


return LibgenAPI
