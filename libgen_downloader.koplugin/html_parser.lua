-- html_parser.lua
-- **PLACEHOLDER** - Handles parsing LibGen HTML content.
-- NOTE: Robust HTML parsing in pure Lua is complex. This uses basic
--       string matching and is VERY LIKELY TO BREAK if LibGen changes layout.
--       A proper HTML parsing library is strongly recommended for production use.

local logger = require("logger")

local HTMLParser = {}

-- Helper to extract text between two patterns (non-greedy, literal)
local function extract_between(str, pattern1, pattern2)
    if not str then return nil end
    local start_pos, end_pos = string.find(str, pattern1, 1, true)
    if not start_pos then return nil end
    start_pos = start_pos + #pattern1

    local content_end, _ = string.find(str, pattern2, start_pos, true)
    if not content_end then return nil end

    return string.sub(str, start_pos, content_end - 1)
end

-- Helper to remove HTML tags and decode basic entities
local function strip_tags(html)
    if not html then return "" end
    -- Basic tag removal
    local text = html:gsub("<[^>]+>", "")
    -- Basic entity decoding
    text = text:gsub(" ", " "):gsub("&", "&"):gsub("<", "<"):gsub(">", ">"):gsub(""", '"')
    -- Trim whitespace
    text = text:gsub("^%s*(.-)%s*$", "%1")
    return text
end

-- Helper to find first href in a string
local function extract_href(html)
    if not html then return nil end
    return html:match('href="([^"]+)"')
end

-- Parses Sci-Tech search results page HTML
function HTMLParser:parse_search_results_scitech(html_content)
    logger.dbg("HTMLParser: Parsing SciTech results...")
    local entries = {}
    -- Target table with class="c", then find tbody. If no tbody, try direct tr in table.
    local table_content = html_content:match('<table class="c"[^>]*>(.-)</table>')
    if not table_content then
        logger.warn("HTMLParser (SciTech): Results table '.c' not found.")
        if html_content:find("No files were found", 1, true) then return {} end
        return nil
    end

    local tbody_content = table_content:match('<tbody>(.-)</tbody>') or table_content -- Fallback if no tbody

    for row_html in tbody_content:gmatch("<tr>(.-)</tr>") do
        local cells_content = {}
        for cell_html in row_html:gmatch("<td[^>]*>(.-)</td>") do
            table.insert(cells_content, cell_html)
        end

        if #cells_content >= 10 then
            local id = strip_tags(cells_content[1])
            local authors = strip_tags(cells_content[2]) -- Simplified author extraction
            local title_html = cells_content[3]
            local title = strip_tags(title_html:match('<a[^>]+id="detailsL[^>]+>(.-)</a>') or title_html) -- Prioritize link text
            local publisher = strip_tags(cells_content[4])
            local year = strip_tags(cells_content[5])
            local pages = strip_tags(cells_content[6])
            local language = strip_tags(cells_content[7])
            local size = strip_tags(cells_content[8])
            local extension = strip_tags(cells_content[9])
            local mirror_html = cells_content[10]
            local mirror = extract_href(mirror_html) or ""

            if id ~= "" and title ~= "" and mirror ~= "" then
                table.insert(entries, {
                    id = id, authors = authors, title = title, publisher = publisher,
                    year = year, pages = pages, language = language, size = size,
                    extension = extension, mirror = mirror, type = "scitech" -- Add type marker
                })
            end
        end
    end
    logger.info("HTMLParser (SciTech): Parsed", #entries, "entries")
    return entries
end

-- Parses Fiction search results page HTML
function HTMLParser:parse_search_results_fiction(html_content, base_mirror)
     logger.dbg("HTMLParser: Parsing Fiction results...")
    local entries = {}
    local table_content = html_content:match('<table class="catalog"[^>]*>(.-)</table>')

    if not table_content then
        logger.warn("HTMLParser (Fiction): Results table '.catalog' not found.")
        if html_content:find("Nothing found", 1, true) then return {} end
        return nil
    end

    local tbody_content = table_content:match('<tbody>(.-)</tbody>') or table_content

    for row_html in tbody_content:gmatch("<tr[^>]*>(.-)</tr>") do -- Allow attributes in <tr>
        local cells_content = {}
        for cell_html in row_html:gmatch("<td[^>]*>(.-)</td>") do
            table.insert(cells_content, cell_html)
        end

        if #cells_content >= 6 then
            -- Authors (cell 1, index 1)
            local authors_html = cells_content[1]
            local authors_list = {}
            for author_link_text in authors_html:gmatch('<a[^>]+>(.-)</a>') do
                table.insert(authors_list, strip_tags(author_link_text))
            end
            local authors = #authors_list > 0 and table.concat(authors_list, ", ") or strip_tags(authors_html)

            -- Series (cell 2, index 2)
            local series = strip_tags(cells_content[2])

            -- Title and Mirror Link (cell 3, index 3)
            local title_html = cells_content[3]
            local title_link_element = title_html:match("(<a[^>]+>.-</a>)") or ""
            local title = strip_tags(title_link_element) -- Get text from link first
                       or strip_tags(title_html)        -- Fallback to whole cell text
            title = title:gsub("%[ed%.[^%]]+%]", ""):gsub("^%s*(.-)%s*$", "%1") -- Clean title
            local relative_mirror = extract_href(title_link_element) or ""

            -- Language (cell 4, index 4)
            local language = strip_tags(cells_content[4])

            -- File Info (cell 5, index 5)
            local file_info = strip_tags(cells_content[5])
            local extension = file_info:match("^(%S+)") or "unknown"
            local size = file_info:match("/%s*(.*)$") or "0 Mb"

            -- MD5 from relative mirror link
            local md5 = relative_mirror:match("([a-fA-F0-9]{32})$") or ""
            local id = md5:lower()

            -- Absolute mirror URL
            local absolute_mirror = ""
             if relative_mirror ~= "" and base_mirror then
                 -- Using LuaSocket URL parsing would be better if available
                 -- Basic joining:
                 local base_scheme, base_host = base_mirror:match("^(https?://[^/]+)")
                 if base_scheme and base_host then
                     if relative_mirror:sub(1,1) == "/" then
                         absolute_mirror = base_scheme .. base_host .. relative_mirror
                     else
                         -- Handle potential relative paths not starting with / ? Unlikely here.
                          absolute_mirror = base_mirror .. "/" .. relative_mirror -- Guessing
                     end
                 else
                     logger.warn("Could not parse base mirror URL:", base_mirror)
                 end
             end

            if id ~= "" and title ~= "" and absolute_mirror ~= "" then
                table.insert(entries, {
                    id = id, authors = authors,
                    title = series ~= "" and string.format("%s (%s)", title, series) or title,
                    publisher = "", year = "", pages = "", language = language,
                    size = size, extension = extension:lower(), mirror = absolute_mirror,
                    type = "fiction" -- Add type marker
                })
            end
        end
    end
     logger.info("HTMLParser (Fiction): Parsed", #entries, "entries")
    return entries
end


-- Parses the FICTION DETAIL page to find the link to the download page (e.g., books.ms)
function HTMLParser:parse_fiction_detail_page_link(html_content)
    -- Find the first href inside <ul class="record_mirrors"> <li> <a ...>
    local link = html_content:match('<ul class="record_mirrors"[^>]*>.-<li><a href="([^"]+)"')
     logger.dbg("HTMLParser: Parsed fiction detail page link:", link or "Not Found")
    return link or nil
end

-- Parses the FINAL DOWNLOAD page (like books.ms or scitech mirror) to find all download links
function HTMLParser:parse_download_page_links(html_content)
     logger.dbg("HTMLParser: Parsing final download page links...")
    local links = {}
    -- Find the main GET link
    local get_link = html_content:match('<div id="download"[^>]*>.-<h2><a href="([^"]+)"')
    if get_link then
         logger.dbg("Found GET link:", get_link)
        table.insert(links, get_link)
    else
        logger.warn("GET link not found on download page.")
    end

    -- Find alternative links (IPFS, Cloudflare, etc.)
    local alternatives_html = extract_between(html_content, '<div id="download"[^>]*>.-<ul>', '</ul>')
    if alternatives_html then
        for link in string.gmatch(alternatives_html, 'href="([^"]+)"') do
            if not string.find(link, "localhost", 1, true) then
                 logger.dbg("Found alternative link:", link)
                table.insert(links, link)
            end
        end
    end

    -- Basic protocol handling for relative '//' links
    for i, link in ipairs(links) do
        if string.sub(link, 1, 2) == "//" then
            links[i] = "https:" .. link
        end
         -- Ensure links start with http (could be relative paths otherwise) - requires base URL
         -- This part is tricky without knowing the base URL of the download server
    end

    -- Remove duplicates
    local unique_links = {}
    local seen = {}
    for _, link in ipairs(links) do
        if not seen[link] then
            table.insert(unique_links, link)
            seen[link] = true
        end
    end

    logger.info("HTMLParser: Found", #unique_links, "unique download links.")
    return #unique_links > 0 and unique_links or nil
end


return HTMLParser
