-- downloader.lua
-- Handles file downloading with progress

local ok_network, NetworkMgr = pcall(require, "ui/network/manager")
local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs") -- Accessing filesystem
local ok_ui, UIManager = pcall(require, "ui/uimanager") -- For scheduling progress updates

if not (ok_network and ok_lfs and ok_ui) then
    error("Downloader: Failed to load dependencies -"..
          " NetworkMgr:"..(ok_network or NetworkMgr)..
          " LFS:"..(ok_lfs or lfs)..
          " UIManager:"..(ok_ui or UIManager))
    return nil
end

local logger = require("logger")

local Downloader = {}

-- url: URL of the file to download
-- target_path: Full path where the file should be saved
-- progress_callback(current_bytes, total_bytes): Called periodically during download
-- complete_callback(success_boolean, error_message_or_nil): Called when download finishes or fails
function Downloader:download_file(url, target_path, progress_callback, complete_callback)
    logger.info("Downloader: Starting download for", url)
    logger.info("Downloader: Target path:", target_path)

    -- Ensure target directory exists
    local dir = lfs.dirname(target_path)
    local dir_exists = lfs.attributes(dir, "mode") == "directory"
    if not dir_exists then
        logger.info("Downloader: Creating directory", dir)
        local ok, err = lfs.mkdir(dir)
        if not ok then
            logger.error("Downloader: Failed to create directory:", dir, "-", err)
            if complete_callback then complete_callback(false, "Failed to create directory: " .. tostring(err)) end
            return
        end
    end

    -- Open file for writing (binary mode)
    local file, err = io.open(target_path, "wb")
    if not file then
        logger.error("Downloader: Failed to open file for writing:", target_path, "-", err)
        if complete_callback then complete_callback(false, "Failed to open file for writing: " .. tostring(err)) end
        return
    end

    local total_bytes = 0
    local current_bytes = 0
    local last_progress_update = 0 -- Track time of last UI update
    local progress_update_interval = 0.5 -- Update UI max every 0.5 seconds

    -- Flag to signal abortion from callbacks
    local aborted = false
    local function abort_download(reason)
        if aborted then return end
        aborted = true
        logger.warn("Downloader: Aborting download -", reason)
        file:close()
        lfs.remove(target_path) -- Clean up partial file
        -- Need a way to cancel the NetworkMgr request if possible
        if complete_callback then complete_callback(false, reason) end
    end

    NetworkMgr:request {
        url = url,
        timeout = 300, -- 5 minutes timeout for downloads
        no_redirects = false, -- Follow redirects
        -- headers = { ["User-Agent"] = "KOReader LibGenPlugin/0.1" },
        sink = function(chunk)
            if aborted then return false end -- Stop processing if aborted
            if not chunk then return true end -- Continue on empty chunk (might happen?)

            local ok, write_err = file:write(chunk)
            if not ok then
                 abort_download("File write error: " .. tostring(write_err))
                 return false -- Signal sink to stop
            end

            current_bytes = current_bytes + #chunk

            -- Throttle progress updates
            local now = os.clock()
            if progress_callback and (now - last_progress_update > progress_update_interval) then
                -- Schedule UI update instead of calling directly from sink
                UIManager:scheduleIn(function()
                    -- Check if still valid before updating UI
                    if not aborted then progress_callback(current_bytes, total_bytes) end
                end, 0)
                last_progress_update = now
            end
            return true -- Continue receiving data
        end,
        onHeaders = function(headers, status_code)
            if aborted then return false end -- Stop processing if aborted
            if status_code and status_code >= 200 and status_code < 300 then
                total_bytes = tonumber(headers:getHeader("content-length") or 0)
                logger.info("Downloader: Total download size:", total_bytes)
                -- Initial progress update via scheduleIn
                if progress_callback then
                    UIManager:scheduleIn(function()
                         if not aborted then progress_callback(current_bytes, total_bytes) end
                    end, 0)
                    last_progress_update = os.clock() -- Reset timer
                end
                return true -- Headers ok, continue
            else
                local reason = "HTTP Error " .. tostring(status_code)
                abort_download(reason)
                return false -- Signal sink/NetworkMgr to stop
            end
        end,
    }
    :onComplete(function(_, headers, status_code)
        if aborted then return end -- Already handled
        logger.info("Downloader: onComplete Status:", status_code)
        file:close()
        if status_code and status_code >= 200 and status_code < 300 then
            -- Final progress update
            if progress_callback then progress_callback(current_bytes, total_bytes) end
            logger.info("Downloader: Download successful:", target_path)
            if complete_callback then complete_callback(true) end
        else
             abort_download(string.format("Download finished with HTTP Error %d", status_code or -1))
        end
    end)
    :onError(function(err_msg)
        if aborted then return end -- Already handled
        abort_download(err_msg or "Unknown download error")
    end)
end

logger.info("Downloader module loaded.")
return Downloader
