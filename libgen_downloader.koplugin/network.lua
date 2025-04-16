-- network.lua
-- Wrapper around KOReader's network capabilities

local NetworkMgr = require("ui/network/manager")
local logger = require("logger")

local Network = {}

-- Basic HTTP GET request
-- callback(success_boolean, response_body_string_or_nil, error_message_or_nil)
function Network:http_get(url, callback)
    logger.dbg("Network GET:", url)
    NetworkMgr:request {
        url = url,
        no_redirects = false, -- Follow redirects by default
        timeout = 30, -- Increased timeout for potentially slow pages
        -- Add User-Agent? Some sites might block default agents.
        -- headers = { ["User-Agent"] = "KOReader LibGenPlugin/0.1" }
    }
    :onComplete(function(response_body, headers, status_code)
        logger.dbg("Network GET complete:", url, "Status:", status_code)
        if status_code and status_code >= 200 and status_code < 300 then
            if callback then callback(true, response_body, headers) end -- Pass headers too
        else
            local err_msg = string.format("HTTP Error %d", status_code or -1)
            logger.warn("Network GET failed:", url, err_msg)
            if callback then callback(false, nil, err_msg) end
        end
    end)
    :onError(function(err_msg)
        logger.error("Network GET error:", url, err_msg)
        if callback then callback(false, nil, err_msg or "Unknown network error") end
    end)
end

-- Basic HTTP Request (allows specifying method, useful for HEAD)
-- callback(success_boolean, response_headers_table_or_nil, error_message_or_nil) for HEAD
-- callback(success_boolean, response_body_string_or_nil, error_message_or_nil) for others
function Network:http_request(method, url, data, options, callback)
    logger.dbg("Network", method, ":", url)
    local request_options = {
        url = url,
        method = method or "GET",
        timeout = options and options.timeout_secs or 20,
        no_redirects = options and options.no_redirects or false,
        -- headers = options and options.headers or { ["User-Agent"] = "KOReader LibGenPlugin/0.1" }
    }
    if method == "POST" and data then
        request_options.post_data = data
    end

    NetworkMgr:request(request_options)
    :onComplete(function(response_body, headers, status_code)
        logger.dbg("Network", method, "complete:", url, "Status:", status_code)
        if status_code and status_code >= 200 and status_code < 300 then
            if method == "HEAD" then
                 if callback then callback(true, headers) end
            else
                 if callback then callback(true, response_body, headers) end -- Pass headers too
            end
        else
            local err_msg = string.format("HTTP Error %d", status_code or -1)
            logger.warn("Network", method, "failed:", url, err_msg)
            if callback then callback(false, nil, err_msg) end
        end
    end)
    :onError(function(err_msg)
        logger.error("Network", method, "error:", url, err_msg)
        if callback then callback(false, nil, err_msg or "Unknown network error") end
    end)
end


return Network
